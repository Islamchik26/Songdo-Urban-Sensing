classdef SongdoSensorApp < handle
    %SONGDOSENSORAPP Causal S3 simulation / CSV-replay dashboard.
    %   app = SongdoSensorApp() uses songdo.core.defaultConfig().
    %   app = SongdoSensorApp(cfg) overlays a scalar configuration struct.
    %   app.start(), app.stop(), app.reset(), and delete(app) are supported.
    %
    %   Base MATLAB R2023b+. No hardware acquisition or network posting is
    %   implemented. Timer time is wall-clock playback time; signal time and
    %   exported UTC timestamps always come from the input and cfg.startUtc.

    properties (SetAccess = private)
        UIFigure
        Config
    end

    properties (Access = private)
        ModeDropDown
        StationDropDown
        ChannelDropDown
        FsField
        CutoffField
        StartUtcField
        ChooseReplayButton
        StartButton
        StopButton
        ResetButton
        ExportButton
        ViewKmaButton
        StateLamp
        StateLabel
        DetailLabel
        SourceLabel
        SampleLabel
        TelemetryTable
        RawAxes
        FilteredAxes
        SpectrumAxes
        RawLine
        FilteredLine
        SpectrumRawLine
        SpectrumFilteredLine
        AcquisitionTimer = []
        Input = table()
        Output = table()
        PlotBuffer = table()
        ProcessorState = []
        NextRow = 1
        BlocksProcessed = 0
        ReplayPath = ''
        RunState = 'Idle'
        Provenance = 'SIMULATED: deterministic synthetic fixture; not KMA observations.'
        Closing = false
        TickBusy = false
        ControlBusy = false
        PlotWindowSeconds = 60
        SpectrumEveryBlocks = 4
    end

    methods
        function app = SongdoSensorApp(cfg)
            base = songdo.core.defaultConfig();
            if nargin > 0 && ~isempty(cfg)
                if ~isstruct(cfg) || ~isscalar(cfg)
                    error('songdo:app:Configuration', ...
                        'Configuration must be a scalar struct.');
                end
                names = fieldnames(cfg);
                for k = 1:numel(names)
                    base.(names{k}) = cfg.(names{k});
                end
            end
            app.Config = base;
            app.validateConfiguration();
            app.ProcessorState = songdo.core.initState(app.Config);
            try
                app.createComponents();
                app.clearDisplay();
                app.setStatus('Idle', ...
                    'Choose a channel, then Start. Running cutoff edits preserve state at the next block.');
                app.UIFigure.Visible = 'on';
            catch exception
                delete(app);
                rethrow(exception);
            end
        end

        function start(app)
            % Start resumes a paused session. At EOF it reruns the same data.
            if app.Closing || app.ControlBusy || strcmp(app.RunState, 'Running')
                return
            end
            if strcmp(app.ModeDropDown.Value, 'hardware')
                app.showError('Hardware unavailable', ...
                    'No hardware adapter is implemented. Select Simulation or CSV replay.');
                return
            end
            app.ControlBusy = true;
            cleanup = onCleanup(@() app.endControlOperation()); %#ok<NASGU>
            app.updateControls();
            try
                app.validateConfiguration();
                if isempty(app.Input)
                    if strcmp(app.ModeDropDown.Value, 'simulation')
                        app.Input = songdo.io.generateScenario(app.Config, ...
                            app.Config.scenario, app.Config.durationSeconds);
                        app.Provenance = sprintf( ...
                            'SIMULATED: scenario %s, seed %d. Not KMA observations.', ...
                            char(string(app.Config.scenario)), app.Config.seed);
                    elseif ~app.loadReplayFromChooser()
                        app.setStatus('Idle', 'CSV selection cancelled. Nothing started.');
                        return
                    end
                end
                if height(app.Input) == 0
                    error('songdo:app:EmptyInput', 'The input contains no samples.');
                end
                if app.NextRow > height(app.Input) || strcmp(app.RunState, 'Error')
                    app.resetProcessing();
                end
                app.disposeTimer();
                app.AcquisitionTimer = timer( ...
                    'Name', 'SongdoSensorApp S3 playback', ...
                    'Tag', 'SongdoSensorAppTimer', ...
                    'ExecutionMode', 'fixedSpacing', ...
                    'Period', app.Config.blockSamples / app.Config.fsHz, ...
                    'StartDelay', 0, ...
                    'TimerFcn', @(source, ~) app.onTimerTick(source), ...
                    'ErrorFcn', @(source, event) app.onTimerError(source, event));
                app.setStatus('Running', ...
                    'Causal block processing. Stop pauses; Reset starts a fresh session.');
                start(app.AcquisitionTimer);
            catch exception
                app.disposeTimer();
                app.setStatus('Error', exception.message);
                app.showError('Cannot start', exception.message);
            end
        end

        function stop(app)
            % Idempotent pause; buffered samples and processor state survive.
            if app.Closing
                return
            end
            wasRunning = strcmp(app.RunState, 'Running');
            app.disposeTimer();
            if wasRunning
                app.setStatus('Paused', ...
                    'Paused. Start resumes without resetting filter or wind-window state.');
            else
                app.updateControls();
            end
        end

        function reset(app)
            % Idempotent reset; retain the selected source, discard outputs.
            if app.Closing || app.ControlBusy
                return
            end
            app.disposeTimer();
            try
                app.resetProcessing();
                app.setStatus('Idle', ...
                    'Processing reset. Start begins at the first input sample.');
            catch exception
                app.setStatus('Error', exception.message);
                app.showError('Reset failed', exception.message);
            end
        end

        function chooseReplay(app, path)
            % Validate a CSV before replacing the current input/session.
            % chooseReplay(app, path) is also useful for a scripted smoke test.
            if app.Closing || app.ControlBusy || strcmp(app.RunState, 'Running')
                return
            end
            app.ControlBusy = true;
            cleanup = onCleanup(@() app.endControlOperation()); %#ok<NASGU>
            app.updateControls();
            try
                if nargin < 2
                    loaded = app.loadReplayFromChooser();
                else
                    app.loadReplay(path);
                    loaded = true;
                end
                if loaded
                    app.setStatus('Ready', ...
                        'CSV validated. Start replays original samples at the configured rate.');
                else
                    app.setStatus(app.RunState, ...
                        'CSV selection cancelled. Existing data and results are unchanged.');
                end
            catch exception
                app.setStatus(app.RunState, ['CSV not loaded: ' exception.message]);
                app.showError('CSV not loaded', exception.message);
            end
        end

        function exportData(app, outputFolder)
            % Export processed samples only. Trailing partial minutes omitted
            % by the shared IO layer; this method does not contact a server.
            if app.Closing || app.ControlBusy || strcmp(app.RunState, 'Running')
                return
            end
            minimumRows = round(60 * app.Config.fsHz);
            if height(app.Output) < minimumRows
                app.showError('No complete minute', ...
                    'Process a full UTC-aligned minute before exporting (at least 600 samples).');
                return
            end
            app.ControlBusy = true;
            cleanup = onCleanup(@() app.endControlOperation()); %#ok<NASGU>
            app.updateControls();
            try
                if nargin < 2
                    outputFolder = uigetdir(pwd, 'Choose folder for local telemetry export');
                    if isequal(outputFolder, 0)
                        app.setStatus(app.RunState, 'Export cancelled. No files were written.');
                        return
                    end
                end
                if ~(ischar(outputFolder) || (isstring(outputFolder) && isscalar(outputFolder)))
                    error('songdo:app:ExportPath', 'Export folder must be a path string.');
                end
                usedInput = app.Input(1:height(app.Output), :);
                songdo.io.exportTelemetry(usedInput, app.Output, app.Config, ...
                    char(outputFolder));
                app.setStatus(app.RunState, sprintf( ...
                    'Local export completed: %s. Complete minutes only; KMA format is a mock.', ...
                    char(outputFolder)));
            catch exception
                app.setStatus(app.RunState, ['Export failed: ' exception.message]);
                app.showError('Export failed', exception.message);
            end
        end

        function [input, output, cfg] = getResults(app)
            % Read-only snapshot for acceptance tests and tuning inspection.
            % cfg is the current configuration; per-row TEMP_CUTOFF_HZ is the
            % authoritative cutoff history when live tuning was used.
            output = app.Output;
            input = app.Input(1:height(output), :);
            cfg = app.Config;
        end

        function delete(app)
            % Stop and delete the owned timer before destroying UI handles.
            if app.Closing
                return
            end
            app.Closing = true;
            app.disposeTimer();
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function validateConfiguration(app)
            cfg = app.Config;
            validateattributes(cfg.fsHz, {'numeric'}, ...
                {'scalar', 'real', 'finite', 'positive'});
            if cfg.fsHz ~= 10
                error('songdo:app:SampleRate', ...
                    'S3 wind processing requires 10 Hz. Set cfg.fsHz = 10.');
            end
            validateattributes(cfg.blockSamples, {'numeric'}, ...
                {'scalar', 'real', 'finite', 'integer', 'positive'});
            validateattributes(cfg.tempLowpassHz, {'numeric'}, ...
                {'scalar', 'real', 'finite', 'positive', '<', cfg.fsHz / 2});
            validateattributes(cfg.durationSeconds, {'numeric'}, ...
                {'scalar', 'real', 'finite', 'positive'});
            for field = {'latitude', 'longitude', 'elevationM'}
                validateattributes(cfg.(field{1}), {'numeric'}, ...
                    {'scalar', 'real', 'finite'});
            end
            app.validateStartUtc(cfg.startUtc);
            if ~strcmp(char(string(cfg.stationId)), 'STATION_CENTRAL_PARK_WEATHER')
                error('songdo:app:Station', 'This app implements only Central Park S3.');
            end
            if abs(cfg.latitude - 37.3930) > 1e-9 || ...
                    abs(cfg.longitude - 126.6345) > 1e-9 || ...
                    abs(cfg.elevationM - 6.2) > 1e-9
                error('songdo:app:StationLocation', ...
                    'Central Park is fixed at 37.3930 N, 126.6345 E, elevation 6.2 m.');
            end
        end

        function openKmaViewer(app)
            % Independent viewer; no changes to simulation input or processing state.
            if app.Closing || app.ControlBusy, return; end
            app.stop();
            try
                observedReport = run_KMA_observations();
                if ~strcmp(observedReport.plot_export_status, 'EXPORTED')
                    app.showError('KMA plot/export unavailable', observedReport.plot_export_status);
                end
            catch exception
                app.showError('Cannot view KMA observations', exception.message);
            end
        end

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'S3 Micro Weather | Simulation / CSV Replay', ...
                'Position', [80 70 1220 820], 'Visible', 'off', ...
                'CloseRequestFcn', @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [5 1]);
            root.RowHeight = {34, 142, '3x', 160, 54};
            root.Padding = [14 12 14 12];
            root.RowSpacing = 10;

            header = uigridlayout(root, [1 3]);
            header.Layout.Row = 1;
            header.ColumnWidth = {'1x', 24, 120};
            header.Padding = [0 0 0 0];
            titleLabel = uilabel(header, 'Text', ...
                'S3 / CENTRAL PARK MICRO WEATHER', 'FontSize', 19, 'FontWeight', 'bold');
            titleLabel.Layout.Column = 1;
            app.StateLamp = uilamp(header, 'Color', [0.55 0.58 0.62]);
            app.StateLamp.Layout.Column = 2;
            app.StateLabel = uilabel(header, 'Text', 'Idle', 'FontWeight', 'bold');
            app.StateLabel.Layout.Column = 3;

            controls = uigridlayout(root, [4 8]);
            controls.Layout.Row = 2;
            controls.RowHeight = {28, 28, 30, 28};
            controls.ColumnWidth = {60, 170, 60, '1x', 70, 88, 70, 100};
            controls.Padding = [0 0 0 0];
            app.addLabel(controls, 'Station', 1, 1);
            app.StationDropDown = uidropdown(controls, ...
                'Items', {'Central Park S3 | 37.3930 N, 126.6345 E | 6.2 m'}, 'Enable', 'off');
            app.StationDropDown.Layout.Row = 1;
            app.StationDropDown.Layout.Column = [2 4];
            app.addLabel(controls, 'Fs (Hz)', 1, 5);
            app.FsField = uieditfield(controls, 'numeric', ...
                'Value', app.Config.fsHz, 'Editable', 'off', ...
                'Tooltip', 'Locked at 10 Hz by the S3 wind requirement.');
            app.FsField.Layout.Row = 1;
            app.FsField.Layout.Column = 6;
            app.addLabel(controls, 'Pole fc (Hz)', 1, 7);
            app.CutoffField = uieditfield(controls, 'numeric', ...
                'Value', app.Config.tempLowpassHz, ...
                'Limits', [0 app.Config.fsHz / 2], ...
                'LowerLimitInclusive', 'off', 'UpperLimitInclusive', 'off', ...
                'Tooltip', ['Temperature cutoff per identical first-order pole. ' ...
                    'Live changes preserve state at the next block; stopped changes reset results.'], ...
                'ValueChangedFcn', @(~, ~) app.onCutoffChanged());
            app.CutoffField.Layout.Row = 1;
            app.CutoffField.Layout.Column = 8;
            app.addLabel(controls, 'Mode', 2, 1);
            app.ModeDropDown = uidropdown(controls, ...
                'Items', {'Simulation', 'CSV replay', 'Hardware (unavailable)'}, ...
                'ItemsData', {'simulation', 'replay', 'hardware'}, ...
                'Value', 'simulation', ...
                'ValueChangedFcn', @(~, ~) app.onModeChanged());
            app.ModeDropDown.Layout.Row = 2;
            app.ModeDropDown.Layout.Column = 2;
            app.ChooseReplayButton = uibutton(controls, 'Text', 'Choose CSV...', ...
                'ButtonPushedFcn', @(~, ~) app.chooseReplay());
            app.ChooseReplayButton.Layout.Row = 2;
            app.ChooseReplayButton.Layout.Column = [3 4];
            app.addLabel(controls, 'Channel', 2, 5);
            app.ChannelDropDown = uidropdown(controls, ...
                'Items', {'Air temperature', 'Relative humidity', 'Wind speed', ...
                    'Wind direction (vector bearing)', 'Pressure (local diagnostic)'}, ...
                'ItemsData', {'AIR_TEMP_C', 'REL_HUMIDITY_PCT', 'WIND_SPEED_MPS', ...
                    'WIND_DIR_DEG', 'PRESSURE_HPA'}, ...
                'Value', 'AIR_TEMP_C', ...
                'ValueChangedFcn', @(~, ~) app.refreshPlots(true));
            app.ChannelDropDown.Layout.Row = 2;
            app.ChannelDropDown.Layout.Column = [6 8];
            app.StartButton = uibutton(controls, 'Text', 'Start', ...
                'ButtonPushedFcn', @(~, ~) app.start());
            app.StartButton.Layout.Row = 3;
            app.StartButton.Layout.Column = [1 2];
            app.StopButton = uibutton(controls, 'Text', 'Stop', ...
                'ButtonPushedFcn', @(~, ~) app.stop());
            app.StopButton.Layout.Row = 3;
            app.StopButton.Layout.Column = 3;
            app.ResetButton = uibutton(controls, 'Text', 'Reset', ...
                'ButtonPushedFcn', @(~, ~) app.reset());
            app.ResetButton.Layout.Row = 3;
            app.ResetButton.Layout.Column = 4;
            app.ExportButton = uibutton(controls, 'Text', 'Export local files...', ...
                'ButtonPushedFcn', @(~, ~) app.exportData());
            app.ExportButton.Layout.Row = 3;
            app.ExportButton.Layout.Column = [5 6];
            app.ViewKmaButton = uibutton(controls, 'Text', 'View real KMA data', ...
                'Tooltip', 'Pauses simulation and opens separate native-cadence observations. No 10 Hz DSP is applied.', ...
                'ButtonPushedFcn', @(~, ~) app.openKmaViewer());
            app.ViewKmaButton.Layout.Row = 3;
            app.ViewKmaButton.Layout.Column = [7 8];
            app.addLabel(controls, 'UTC base', 4, 1);
            app.StartUtcField = uieditfield(controls, 'text', ...
                'Value', char(string(app.Config.startUtc)), ...
                'Tooltip', ['Export UTC = this whole-minute UTC anchor + time_s. ' ...
                    'CSV replay does not infer or verify a real observation timestamp.'], ...
                'ValueChangedFcn', @(~, ~) app.onStartUtcChanged());
            app.StartUtcField.Layout.Row = 4;
            app.StartUtcField.Layout.Column = [2 4];
            anchorNote = app.addLabel(controls, ...
                'CSV UTC is assigned from this base, not recovered from observations.', 4, [5 8]);
            anchorNote.FontSize = 11;

            plots = uigridlayout(root, [2 2]);
            plots.Layout.Row = 3;
            plots.RowHeight = {'1x', '1x'};
            plots.ColumnWidth = {'1x', '1x'};
            plots.Padding = [0 0 0 0];
            app.RawAxes = uiaxes(plots);
            app.RawAxes.Layout.Row = 1;
            app.RawAxes.Layout.Column = 1;
            app.FilteredAxes = uiaxes(plots);
            app.FilteredAxes.Layout.Row = 1;
            app.FilteredAxes.Layout.Column = 2;
            app.SpectrumAxes = uiaxes(plots);
            app.SpectrumAxes.Layout.Row = 2;
            app.SpectrumAxes.Layout.Column = [1 2];
            app.RawLine = plot(app.RawAxes, NaN, NaN, 'Color', [0.67 0.39 0.15], 'LineWidth', 1.1);
            app.FilteredLine = plot(app.FilteredAxes, NaN, NaN, 'Color', [0.05 0.42 0.58], 'LineWidth', 1.4);
            app.SpectrumRawLine = plot(app.SpectrumAxes, NaN, NaN, ...
                'Color', [0.67 0.39 0.15], 'DisplayName', 'Raw');
            hold(app.SpectrumAxes, 'on');
            app.SpectrumFilteredLine = plot(app.SpectrumAxes, NaN, NaN, ...
                'Color', [0.05 0.42 0.58], 'DisplayName', 'Processed');
            hold(app.SpectrumAxes, 'off');
            grid(app.RawAxes, 'on');
            grid(app.FilteredAxes, 'on');
            grid(app.SpectrumAxes, 'on');
            xlabel(app.RawAxes, 'Input time (s)');
            xlabel(app.FilteredAxes, 'Input time (s)');
            xlabel(app.SpectrumAxes, 'Frequency (Hz)');
            legend(app.SpectrumAxes, 'Location', 'northeast');
            xlim(app.SpectrumAxes, [0 app.Config.fsHz / 2]);

            summary = uigridlayout(root, [2 1]);
            summary.Layout.Row = 4;
            summary.RowHeight = {22, '1x'};
            summary.Padding = [0 0 0 0];
            app.SampleLabel = uilabel(summary, 'Text', 'No processed samples', ...
                'FontWeight', 'bold');
            app.TelemetryTable = uitable(summary, ...
                'ColumnName', {'Channel', 'Raw', 'Processed', 'Unit', 'Quality / state'}, ...
                'ColumnWidth', {230, 120, 120, 80, 'auto'}, ...
                'RowName', {}, 'ColumnEditable', false(1, 5));
            app.TelemetryTable.Layout.Row = 2;
            footer = uigridlayout(root, [2 1]);
            footer.Layout.Row = 5;
            footer.RowHeight = {24, 24};
            footer.Padding = [0 0 0 0];
            app.SourceLabel = uilabel(footer, 'Text', app.Provenance, ...
                'FontColor', [0.4 0.27 0.05], 'WordWrap', 'on');
            app.DetailLabel = uilabel(footer, 'Text', '', 'WordWrap', 'on');
            app.DetailLabel.Layout.Row = 2;
        end

        function label = addLabel(~, parent, textValue, row, column)
            label = uilabel(parent, 'Text', textValue);
            label.Layout.Row = row;
            label.Layout.Column = column;
        end

        function onModeChanged(app)
            if app.Closing || app.ControlBusy
                return
            end
            app.disposeTimer();
            app.Input = table();
            app.ReplayPath = '';
            app.resetProcessing();
            switch app.ModeDropDown.Value
                case 'simulation'
                    app.Provenance = 'SIMULATED: deterministic synthetic fixture; not KMA observations.';
                    message = 'Simulation selected. Start generates the configured synthetic scenario.';
                case 'replay'
                    app.Provenance = 'CSV REPLAY: user-provided samples; provenance not independently verified.';
                    message = 'Choose a CSV, or press Start to select one. Previous results cleared.';
                otherwise
                    app.Provenance = 'HARDWARE UNAVAILABLE: no device is connected or acquired by this app.';
                    message = 'Hardware requires an adapter. Simulation and CSV replay are implemented.';
            end
            app.setStatus('Idle', message);
        end

        function onCutoffChanged(app)
            if app.Closing || app.ControlBusy
                return
            end
            previous = app.Config;
            running = strcmp(app.RunState, 'Running');
            try
                candidate = app.Config;
                candidate.tempLowpassHz = app.CutoffField.Value;
                % Validate before commit. UI callbacks cannot interrupt this
                % app's block processing (drawnow uses nocallbacks), so this
                % coefficient change takes effect at the next block boundary.
                candidate = songdo.dsp.validateConfig(candidate);
                app.Config = candidate;
                if running
                    % Preserve pole states, derivative reference, windows,
                    % output rows, and next cursor. Do not restart the timer.
                    % The core records TEMP_CUTOFF_HZ on every processed row.
                    app.setStatus('Running', sprintf( ...
                        'Pole cutoff %.4g Hz applies next block; state retained. A retuning transient is expected.', ...
                        app.Config.tempLowpassHz));
                else
                    app.resetProcessing();
                    app.setStatus('Idle', ...
                        'Stopped cutoff edit: old outputs cleared for a fresh fixed-setting run.');
                end
            catch exception
                app.Config = previous;
                app.CutoffField.Value = previous.tempLowpassHz;
                app.showError('Invalid cutoff', exception.message);
            end
        end


        function validateStartUtc(~, value)
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                error('songdo:app:StartUtc', 'UTC base must be an ISO-8601 text value.');
            end
            textValue = char(value);
            if isempty(regexp(textValue, ...
                    '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00\.000Z$', 'once'))
                error('songdo:app:StartUtc', ...
                    'Use a whole UTC minute, for example 2026-01-01T00:00:00.000Z.');
            end
            anchor = datetime(textValue, ...
                'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', 'TimeZone', 'UTC');
            if isnat(anchor)
                error('songdo:app:StartUtc', 'UTC base is not a valid date/time.');
            end
        end

        function onStartUtcChanged(app)
            if app.Closing || app.ControlBusy || strcmp(app.RunState, 'Running')
                app.StartUtcField.Value = char(string(app.Config.startUtc));
                return
            end
            previous = app.Config.startUtc;
            try
                nextValue = strtrim(app.StartUtcField.Value);
                app.validateStartUtc(nextValue);
                app.Config.startUtc = nextValue;
                if ~isempty(app.Input) && isstruct(app.Input.Properties.UserData)
                    app.Input.Properties.UserData.startUtc = nextValue;
                end
                app.resetProcessing();
                app.setStatus('Idle', ...
                    'UTC anchor updated; old outputs cleared. This does not establish observed provenance.');
            catch exception
                app.Config.startUtc = previous;
                app.StartUtcField.Value = char(string(previous));
                app.showError('Invalid UTC anchor', exception.message);
            end
        end

        function loaded = loadReplayFromChooser(app)
            loaded = false;
            [file, folder] = uigetfile({'*.csv', 'S3 input CSV (*.csv)'}, ...
                'Select a 10 Hz S3 input CSV');
            if isequal(file, 0)
                return
            end
            app.loadReplay(fullfile(folder, file));
            loaded = true;
        end

        function loadReplay(app, path)
            if ~(ischar(path) || (isstring(path) && isscalar(path)))
                error('songdo:app:ReplayPath', 'CSV path must be a path string.');
            end
            nextInput = songdo.io.readReplay(char(path), app.Config);
            nextState = songdo.core.initState(app.Config);
            % Commit only after both adapter validation and state construction.
            app.Input = nextInput;
            app.ProcessorState = nextState;
            app.ReplayPath = char(path);
            app.ModeDropDown.Value = 'replay';
            app.Provenance = sprintf( ...
                'CSV REPLAY: %s | No source authenticity or KMA provenance is claimed.', ...
                app.ReplayPath);
            app.resetProcessing();
        end

        function resetProcessing(app)
            nextState = songdo.core.initState(app.Config);
            app.Output = table();
            app.PlotBuffer = table();
            app.ProcessorState = nextState;
            app.NextRow = 1;
            app.BlocksProcessed = 0;
            app.clearDisplay();
        end

        function onTimerTick(app, source)
            if app.Closing || app.TickBusy || ~strcmp(app.RunState, 'Running') || ...
                    isempty(app.AcquisitionTimer) || ~isequal(source, app.AcquisitionTimer)
                return
            end
            app.TickBusy = true;
            cleanup = onCleanup(@() app.releaseTick()); %#ok<NASGU>
            try
                first = app.NextRow;
                last = min(first + app.Config.blockSamples - 1, height(app.Input));
                if first > last
                    app.finishPlayback();
                    return
                end
                block = app.Input(first:last, :);
                [processed, nextState] = songdo.core.processBlock( ...
                    block, app.ProcessorState, app.Config);
                if height(processed) ~= height(block)
                    error('songdo:app:ProcessorLength', ...
                        'Processor output must have one row per input sample.');
                end
                % Processing is transactional: never advance on a core error.
                app.ProcessorState = nextState;
                app.Output = app.appendTable(app.Output, processed);
                app.PlotBuffer = app.appendTable(app.PlotBuffer, processed);
                maxRows = max(2, round(app.PlotWindowSeconds * app.Config.fsHz));
                if height(app.PlotBuffer) > maxRows
                    app.PlotBuffer = app.PlotBuffer(end-maxRows+1:end, :);
                end
                app.NextRow = last + 1;
                app.BlocksProcessed = app.BlocksProcessed + 1;
                app.refreshPlots(mod(app.BlocksProcessed, app.SpectrumEveryBlocks) == 0 ...
                    || app.BlocksProcessed == 1);
                app.refreshTable();
                if app.NextRow > height(app.Input)
                    app.finishPlayback();
                end
                drawnow limitrate nocallbacks
            catch exception
                app.disposeTimer();
                app.setStatus('Error', exception.message);
                app.showError('Processing stopped', exception.message);
            end
        end

        function result = appendTable(~, existing, block)
            if isempty(existing)
                result = block;
            else
                result = [existing; block];
            end
        end

        function finishPlayback(app)
            app.disposeTimer();
            app.refreshPlots(true);
            app.setStatus('Completed', ...
                'End of input. Export complete minutes, or Start to replay from the beginning.');
        end

        function onTimerError(app, source, event)
            if app.Closing || isempty(app.AcquisitionTimer) || ...
                    ~isequal(source, app.AcquisitionTimer)
                return
            end
            message = 'The playback timer stopped unexpectedly.';
            try
                message = event.Data.Message;
            catch
                % Timer event payload differs across releases; retain fallback.
            end
            app.disposeTimer();
            app.setStatus('Error', message);
            app.showError('Timer error', message);
        end

        function disposeTimer(app)
            ownedTimer = app.AcquisitionTimer;
            app.AcquisitionTimer = [];
            if isempty(ownedTimer) || ~isvalid(ownedTimer)
                return
            end
            try
                stop(ownedTimer);
            catch exception
                warning('songdo:app:TimerStop', 'Could not stop playback timer: %s', exception.message);
            end
            if isvalid(ownedTimer)
                delete(ownedTimer);
            end
        end

        function releaseTick(app)
            if isvalid(app)
                app.TickBusy = false;
            end
        end

        function endControlOperation(app)
            if isvalid(app) && ~app.Closing
                app.ControlBusy = false;
                app.updateControls();
            end
        end

        function setStatus(app, state, detail)
            app.RunState = state;
            if app.Closing || isempty(app.UIFigure) || ~isgraphics(app.UIFigure)
                return
            end
            app.StateLabel.Text = state;
            app.DetailLabel.Text = detail;
            app.SourceLabel.Text = app.Provenance;
            switch state
                case 'Running'
                    app.StateLamp.Color = [0.08 0.60 0.32];
                case {'Paused', 'Ready'}
                    app.StateLamp.Color = [0.88 0.57 0.10];
                case 'Error'
                    app.StateLamp.Color = [0.84 0.18 0.18];
                otherwise
                    app.StateLamp.Color = [0.48 0.53 0.59];
            end
            app.updateControls();
        end

        function updateControls(app)
            if app.Closing || isempty(app.StartButton) || ~isvalid(app.StartButton)
                return
            end
            running = strcmp(app.RunState, 'Running');
            canEdit = ~running && ~app.ControlBusy;
            app.StartButton.Enable = app.onOff(canEdit && ...
                ~strcmp(app.ModeDropDown.Value, 'hardware'));
            app.StopButton.Enable = app.onOff(running && ~app.ControlBusy);
            app.ResetButton.Enable = app.onOff(~app.ControlBusy);
            app.ViewKmaButton.Enable = app.onOff(~app.ControlBusy);
            app.ExportButton.Enable = app.onOff(canEdit && ...
                height(app.Output) >= round(60 * app.Config.fsHz));
            app.ModeDropDown.Enable = app.onOff(canEdit);
            app.CutoffField.Enable = app.onOff(~app.ControlBusy);
            app.StartUtcField.Enable = app.onOff(canEdit);
            app.ChooseReplayButton.Enable = app.onOff(canEdit && ...
                strcmp(app.ModeDropDown.Value, 'replay'));
            app.ChannelDropDown.Enable = app.onOff(~app.ControlBusy);
            if strcmp(app.RunState, 'Completed')
                app.StartButton.Text = 'Run again';
            elseif strcmp(app.RunState, 'Paused')
                app.StartButton.Text = 'Resume';
            else
                app.StartButton.Text = 'Start';
            end
        end

        function value = onOff(~, condition)
            if condition
                value = 'on';
            else
                value = 'off';
            end
        end

        function clearDisplay(app)
            if isempty(app.UIFigure) || ~isgraphics(app.UIFigure)
                return
            end
            app.RawLine.XData = NaN;
            app.RawLine.YData = NaN;
            app.FilteredLine.XData = NaN;
            app.FilteredLine.YData = NaN;
            app.clearSpectrum();
            app.RawAxes.XLimMode = 'auto';
            app.FilteredAxes.XLimMode = 'auto';
            app.SampleLabel.Text = 'No processed samples';
            app.TelemetryTable.Data = cell(0, 5);
            app.refreshPlots(true);
        end

        function refreshPlots(app, updateSpectrum)
            if app.Closing || isempty(app.UIFigure) || ~isgraphics(app.UIFigure)
                return
            end
            channel = app.ChannelDropDown.Value;
            [raw, filtered, unit, description] = app.channelData(app.PlotBuffer, channel);
            title(app.RawAxes, ['Raw: ' description]);
            title(app.FilteredAxes, ['Processed: ' description]);
            ylabel(app.RawAxes, unit);
            ylabel(app.FilteredAxes, unit);
            if isempty(app.PlotBuffer)
                app.clearSpectrum();
                title(app.SpectrumAxes, 'One-sided Hann amplitude (mean removed): waiting for samples');
                return
            end
            times = app.PlotBuffer.time_s;
            app.RawLine.XData = times;
            app.RawLine.YData = raw;
            app.FilteredLine.XData = times;
            app.FilteredLine.YData = filtered;
            span = [max(times(1), times(end) - app.PlotWindowSeconds), times(end)];
            if span(1) == span(2)
                span = span + [-0.5 0.5] / app.Config.fsHz;
            end
            xlim(app.RawAxes, span);
            xlim(app.FilteredAxes, span);
            if updateSpectrum
                app.refreshSpectrum(raw, filtered, unit, channel);
            end
        end

        function [raw, filtered, unit, description] = channelData(app, data, channel)
            raw = [];
            filtered = [];
            switch channel
                case 'AIR_TEMP_C'
                    unit = 'deg C'; description = 'air temperature';
                    if ~isempty(data)
                        raw = data.AIR_TEMP_C;
                        filtered = data.AIR_TEMP_FILTERED_C;
                    end
                case 'REL_HUMIDITY_PCT'
                    unit = '% RH'; description = 'relative humidity';
                    if ~isempty(data)
                        raw = data.REL_HUMIDITY_PCT;
                        filtered = data.REL_HUMIDITY_FILTERED_PCT;
                    end
                case 'WIND_SPEED_MPS'
                    unit = 'm/s'; description = 'wind speed (10 s vector mean)';
                    if ~isempty(data)
                        raw = data.WIND_SPEED_MPS;
                        filtered = data.WIND_MEAN_SPEED_MPS;
                    end
                case 'WIND_DIR_DEG'
                    unit = 'deg'; description = 'wind vector bearing (not meteorological from)';
                    if ~isempty(data)
                        raw = mod(atan2d(data.WIND_U_MPS, data.WIND_V_MPS), 360);
                        raw(~isfinite(data.WIND_U_MPS) | ~isfinite(data.WIND_V_MPS) | ...
                            hypot(data.WIND_U_MPS, data.WIND_V_MPS) <= app.Config.windCalmThresholdMps) = NaN;
                        filtered = data.WIND_MEAN_DIR_DEG;
                    end
                otherwise
                    unit = 'hPa'; description = 'local pressure / sea-level reduction';
                    if ~isempty(data)
                        raw = data.PRESSURE_HPA;
                        filtered = data.SEA_LEVEL_PRESSURE_HPA;
                    end
            end
        end

        function refreshSpectrum(app, raw, filtered, unit, channel)
            if strcmp(channel, 'WIND_DIR_DEG')
                app.clearSpectrum();
                title(app.SpectrumAxes, ...
                    'Direction is circular: a scalar FFT of wrapped degrees is not shown');
                ylabel(app.SpectrumAxes, 'Amplitude');
                return
            end
            [rawFrequency, rawAmplitude] = app.spectrumOfValidTail(raw);
            [filteredFrequency, filteredAmplitude] = app.spectrumOfValidTail(filtered);
            app.SpectrumRawLine.XData = rawFrequency;
            app.SpectrumRawLine.YData = rawAmplitude;
            app.SpectrumFilteredLine.XData = filteredFrequency;
            app.SpectrumFilteredLine.YData = filteredAmplitude;
            ylabel(app.SpectrumAxes, ['Amplitude (' unit ')']);
            title(app.SpectrumAxes, ...
                'One-sided Hann amplitude: mean removed, latest contiguous valid samples (max 60 s)');
            if all(isnan(rawFrequency)) && all(isnan(filteredFrequency))
                title(app.SpectrumAxes, ...
                    'Spectrum waiting for at least 16 contiguous valid samples; gaps are not interpolated');
            end
        end

        function [frequency, amplitude] = spectrumOfValidTail(app, values)
            frequency = NaN;
            amplitude = NaN;
            if isempty(values)
                return
            end
            lastBad = find(~isfinite(values), 1, 'last');
            if ~isempty(lastBad)
                values = values(lastBad+1:end);
            end
            if numel(values) < 16
                return
            end
            values = values(:) - mean(values);
            [frequency, amplitude] = songdo.dsp.oneSidedSpectrum(values, app.Config.fsHz);
        end

        function clearSpectrum(app)
            app.SpectrumRawLine.XData = NaN;
            app.SpectrumRawLine.YData = NaN;
            app.SpectrumFilteredLine.XData = NaN;
            app.SpectrumFilteredLine.YData = NaN;
        end

        function refreshTable(app)
            data = app.Output(end, :);
            names = {'Air temperature'; 'Relative humidity'; 'Wind speed'; ...
                'Wind direction'; 'Pressure (local diagnostic)'};
            channels = {'AIR_TEMP_C', 'REL_HUMIDITY_PCT', 'WIND_SPEED_MPS', ...
                'WIND_DIR_DEG', 'PRESSURE_HPA'};
            flags = {char(string(data.TEMP_QUALITY)), char(string(data.HUMIDITY_QUALITY)), ...
                char(string(data.WIND_QUALITY)), char(string(data.WIND_QUALITY)), ...
                char(string(data.PRESSURE_QUALITY))};
            if ~isfinite(data.WIND_MEAN_DIR_DEG)
                if isfinite(data.WIND_MEAN_SPEED_MPS) && ...
                        data.WIND_MEAN_SPEED_MPS <= app.Config.windCalmThresholdMps
                    flags{4} = 'CALM / UNDEFINED (display)';
                else
                    flags{4} = 'UNDEFINED (display)';
                end
            end
            rows = cell(5, 5);
            for k = 1:5
                [raw, filtered, unit] = app.channelData(data, channels{k});
                rows(k, :) = {names{k}, app.formatNumber(raw), app.formatNumber(filtered), unit, flags{k}};
            end
            app.TelemetryTable.Data = rows;
            if data.WIND_WINDOW_COMPLETE
                windowText = '10 s window complete';
            else
                windowText = 'wind window warming up / incomplete';
            end
            app.SampleLabel.Text = sprintf( ...
                't = %.1f s | %d / %d samples | gust (3 s max): %s m/s | %s', ...
                data.time_s, height(app.Output), height(app.Input), ...
                app.formatNumber(data.WIND_GUST_MPS), windowText);
        end

        function textValue = formatNumber(~, value)
            if isempty(value) || ~isfinite(value)
                textValue = '--';
            else
                textValue = sprintf('%.3f', value);
            end
        end

        function showError(app, titleText, message)
            if ~app.Closing && ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                uialert(app.UIFigure, message, titleText, 'Icon', 'error');
            end
        end
    end
end
