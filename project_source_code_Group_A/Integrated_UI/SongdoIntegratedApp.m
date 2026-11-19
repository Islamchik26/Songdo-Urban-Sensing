classdef SongdoIntegratedApp < handle
%SONGDOINTEGRATEDAPP  Team A integrated engineering instrument (S1-S5).
%
%   app = SongdoIntegratedApp();     % or simply:  launch_songdo
%
%   One window to choose and run ANY station (S1..S5) or ANY scenario
%   (Sx-1 .. Sx-5) of the Songdo Urban Sensing handbook, using each team
%   member's ORIGINAL code unchanged:
%
%     Task Runner      tree of 5 stations x 5 scenarios -> run, embedded
%                      member figures, handbook target vs measured checks,
%                      console excerpt, telemetry JSON preview
%     Live Instrument  handbook Section 5 oscilloscope: dual trace raw vs
%                      causal filtered, Hann-corrected one-sided spectrum,
%                      7-stage signal-chain strip, live cutoff tuning,
%                      telemetry buffer, Sensor Grid JSON/CSV export
%     Verification     every member's test suite + cross-station checks
%     Station Map      clickable WGS84 map, Haversine distances, grid
%                      schema conformance of all five exports
%     Log              full captured console of everything that ran
%
%   Programmatic App (uifigure / uiaxes / uitable), base MATLAB R2023b+.
%   Public methods (selectNode, runSelected, runAllStations, liveStart,
%   liveStop, liveStep, runVerificationSuites, validateAllExports) make the
%   instrument scriptable and testable.

    properties (SetAccess = private)
        UIFigure
        Registry
        Cache            % containers.Map: station code -> run result
        Theme = 'dark'   % 'dark' | 'light'  (header toggle or setTheme)
    end

    properties (Access = private)
        % header / navigation
        HeaderGrid
        ThemeButton
        StatusLabel
        Tree
        NodeByKey        % containers.Map: 'S1' / 'S1-3' -> tree node
        RunButton
        RunStationButton
        RerunButton
        FolderButton
        MemberAppButton
        Tabs
        TabTask
        TabLive
        TabVerify
        TabMap
        TabLog
        % task runner
        TaskTitle
        TaskSpec
        TaskMeta
        ViewDrop
        PopButton
        ViewImage
        ViewText
        ChecksTable
        ConsoleArea
        Card
        ViewPanel
        Views = struct('label', {}, 'kind', {}, 'fig', {}, 'png', {}, 'text', {})
        CropCache        % containers.Map: task id -> cropped figure
        Sel = struct('code', 'S1', 'task', '')
        % live instrument
        StageLabels
        LiveStation
        LiveChannel
        FsLabel
        CutoffField
        StartButton
        StopButton
        ResetButton
        ExportButton
        LiveState
        FeatureLabel
        SourceLabel
        ScopeAx
        SpecAx
        RawLine
        FiltLine
        SpecRawLine
        SpecFiltLine
        NyqLine
        TeleTable
        Stream = []
        LiveTimer = []
        TickBusy = false
        RawT = zeros(0, 1)
        RawX = zeros(0, 1)
        FiltT = zeros(0, 1)
        FiltY = zeros(0, 1)
        Records = struct('timestamp', {}, 'channel', {}, 'raw_value', {}, ...
            'filtered_value', {}, 'unit', {}, 'quality_flag', {})
        StartUtc
        % verification / map / log
        VerifyTable
        VerifyHint
        VerifyLog
        MapAx            % geoaxes with a real basemap
        MapBase
        MapMode
        MapInfo
        MapOpenButton
        MapLabels
        MapLabelBase = {}
        MapSel = 'S1'
        MapLimitsSet = false
        MapSiteExt = 100*ones(1, 5)   % metres: half-size of each site overlay (Zoom to site)
        MapHistAx        % history chart of the selected station (replaces distance table)
        MapSiteText = ''
        Placement        % containers.Map code -> struct(lat, lon, headingDeg); site_placement.json
        PlacingSite = false
        PlaceButton
        RotLeftButton
        RotRightButton
        ResetSiteButton
        GridTable
        LogArea
        LogText = ''
        ViewDir
    end

    properties (Constant, Access = private)
        Accent = [0.13 0.55 0.85]
    end

    % =====================================================================
    methods
        function app = SongdoIntegratedApp()
            app.Registry = songdoui.setupPaths();
            app.Cache = containers.Map();
            app.Placement = songdoui.sitePlacement('load');
            app.CropCache = containers.Map();
            app.NodeByKey = containers.Map();
            app.ViewDir = fullfile(tempdir, 'songdoui_views');
            if ~isfolder(app.ViewDir), mkdir(app.ViewDir); end
            app.StartUtc = datetime('now', 'TimeZone', 'UTC');
            app.buildUI();
            app.log(sprintf('Integrated instrument started (MATLAB %s). Group root:\n  %s', ...
                version('-release'), app.Registry.groupRoot));
            app.selectNode('S1');
            app.onLiveStationChanged();
            app.validateAllExports();          % also draws the map
            app.UIFigure.Visible = 'on';
        end

        function delete(app)
            app.stopTimer();
            keys = app.Cache.keys;
            for k = 1:numel(keys)
                r = app.Cache(keys{k});
                delete(r.figures(isvalid(r.figures)));
            end
            ck = app.CropCache.values;
            for k = 1:numel(ck), if isvalid(ck{k}), delete(ck{k}); end, end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure), delete(app.UIFigure); end
        end

        % ------------------------------------------------ public actions
        function selectNode(app, key)
            %SELECTNODE  Select 'S3' (station) or 'S3-1' (scenario) by code.
            if ~app.NodeByKey.isKey(key), error('songdoui:key', 'Unknown node %s', key); end
            node = app.NodeByKey(key);
            app.Tree.SelectedNodes = node;
            if isempty(node.NodeData.task), expand(node); else, expand(node.Parent); end
            app.applySelection(node.NodeData);
        end

        function runSelected(app, force)
            %RUNSELECTED  Run the station that owns the current selection.
            if nargin < 2, force = false; end
            st = app.station(app.Sel.code);
            if force || ~app.Cache.isKey(st.code)
                app.runStationNow(st);
            end
            app.Tabs.SelectedTab = app.TabTask;
            app.applySelection(app.Sel);
        end

        function runAllStations(app)
            %RUNALLSTATIONS  Unified end-to-end run of all five pipelines.
            app.liveStop();
            d = uiprogressdlg(app.UIFigure, 'Title', 'Unified run: all five stations', ...
                'Message', 'Starting...', 'Cancelable', 'on');
            S = app.Registry.stations;
            for k = 1:numel(S)
                if d.CancelRequested, break; end
                d.Value = (k - 1)/numel(S);
                d.Message = sprintf('%s %s - %s', S(k).code, S(k).name, S(k).entry);
                app.runStationNow(S(k), false);
            end
            close(d);
            app.validateAllExports();
            app.applySelection(app.Sel);
            app.summaryAlert();
        end

        function liveStart(app)
            if isempty(app.Stream), app.onLiveChannelChanged(); end
            app.stopTimer();
            app.LiveTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, ...
                'BusyMode', 'drop', 'Name', 'SongdoIntegratedLive', ...
                'TimerFcn', @(~, ~) app.onTick(), ...
                'ErrorFcn', @(~, e) app.onTimerError(e));
            start(app.LiveTimer);
            app.setLiveButtons(true);
            app.status(sprintf('LIVE: %s / %s streaming (causal, persistent state)', ...
                app.Stream.Code, app.Stream.Channel));
        end

        function liveStop(app)
            app.stopTimer();
            if ~isempty(app.StartButton) && isvalid(app.StartButton)
                app.setLiveButtons(false);
            end
        end

        function liveStep(app, n)
            %LIVESTEP  Advance the live instrument n blocks without the timer.
            if nargin < 2, n = 1; end
            if isempty(app.Stream), app.onLiveChannelChanged(); end
            for k = 1:n, app.processBlock(mod(k, 4) == 0 || k == n); end
        end

        function setTheme(app, mode)
            %SETTHEME  'dark' or 'light'. Member plots keep their own (white) look.
            app.Theme = validatestring(mode, {'dark', 'light'});
            app.applyTheme();
        end

        function mapShow(app, code, showMode, basemap)
            %MAPSHOW  Map tab: select station CODE, optionally set the view
            %   ('stations' | 'readings' | 'grid' | 'site' for CODE's site view)
            %   and basemap ('topographic' | 'streets' | 'satellite' | 'darkwater').
            if nargin > 3 && ~isempty(basemap), app.MapBase.Value = basemap; end
            app.Tabs.SelectedTab = app.TabMap;
            if nargin > 2 && strcmp(showMode, 'site'), showMode = ['site:' code]; end
            app.MapSel = code;
            if nargin > 2 && ~isempty(showMode)
                app.MapMode.Value = showMode;
                app.onMapMode();
            else
                app.mapSelect(code);
            end
        end

        function placeSite(app, code, lat, lon, headingDeg)
            %PLACESITE  Move CODE's site overlay to (lat, lon); optional heading
            %   (degrees counter-clockwise from east, used by the S1 area). Saved
            %   to site_placement.json. The handbook station point is unchanged.
            st = app.station(code);
            if nargin < 5 || isempty(headingDeg)
                [~, ~, headingDeg] = app.siteCenter(st);
            end
            app.Placement(code) = struct('lat', lat, 'lon', lon, 'headingDeg', headingDeg);
            songdoui.sitePlacement('save', app.Placement);
            d = 1000*songdoui.haversineKm([st.lat lat], [st.lon lon]);
            app.log(sprintf('%s site overlay placed at %.6f N, %.6f E (%.0f m from the handbook station point)', code, lat, lon, d(1, 2)));
            app.MapSel = code;
            app.drawMap();
        end

        function rotateSite(app, code, dDeg)
            %ROTATESITE  Turn CODE's site overlay by dDeg (counter-clockwise positive).
            [la, lo, hd] = app.siteCenter(app.station(code));
            app.placeSite(code, la, lo, mod(hd + dDeg, 360));
        end

        function resetSite(app, code)
            %RESETSITE  Put CODE's site overlay back on the handbook station point.
            if app.Placement.isKey(code), app.Placement.remove(code); end
            songdoui.sitePlacement('save', app.Placement);
            app.log(sprintf('%s site overlay reset to the handbook station point', code));
            app.MapSel = code;
            app.drawMap();
        end

        function mapMove(app, dir)
            %MAPMOVE  'north' | 'south' | 'east' | 'west' | 'in' | 'out' | 'site' | 'reset'
            if strcmp(dir, 'reset'), app.resetMapView(); else, app.mapNav(dir); end
        end

        function showTab(app, name)
            %SHOWTAB  'task' | 'live' | 'verify' | 'map' | 'log'
            tabs = struct('task', app.TabTask, 'live', app.TabLive, 'verify', app.TabVerify, ...
                'map', app.TabMap, 'log', app.TabLog);
            app.Tabs.SelectedTab = tabs.(lower(name));
        end

        function liveSelect(app, code, channel)
            %LIVESELECT  Choose station (and channel) on the live instrument.
            app.LiveStation.Value = code;
            app.onLiveStationChanged();
            if nargin > 2
                app.LiveChannel.Value = channel;
                app.onLiveChannelChanged();
            end
            app.Tabs.SelectedTab = app.TabLive;
        end

        function liveRetune(app, fc)
            %LIVERETUNE  Change the cutoff while streaming (state retained).
            app.CutoffField.Value = fc;
            app.onCutoffChanged();
        end

        function file = liveExport(app)
            %LIVEEXPORT  Write the telemetry buffer as Sensor Grid JSON + CSV.
            file = app.exportLive(false);
        end

        function T = runVerificationSuites(app)
            app.liveStop();
            d = uiprogressdlg(app.UIFigure, 'Title', 'Verification suites', 'Message', 'Starting...');
            cleanup = onCleanup(@() close(d));
            [T, txt] = songdoui.runVerification(app.Registry, ...
                @(v, msg) setProgress(d, v, msg));
            app.VerifyTable.Data = T;
            app.styleResultTable(app.VerifyTable, T.Result);
            app.VerifyLog.Value = splitlines(string(txt));
            app.log(['=== Verification suites ===' newline txt]);
            nP = sum(strcmp(T.Result, 'PASS')); nF = sum(strcmp(T.Result, 'FAIL'));
            app.status(sprintf('Verification: %d PASS, %d FAIL, %d other', nP, nF, height(T) - nP - nF));
            app.Tabs.SelectedTab = app.TabVerify;
        end

        function T = validateAllExports(app)
            S = app.Registry.stations;
            rows = cell(numel(S), 5);
            for k = 1:numel(S)
                st = S(k);
                if isfile(st.jsonFile)
                    v = songdoui.validateSensorGrid(st.jsonFile, app.Registry);
                    res = 'PASS'; if ~v.ok, res = 'FAIL'; elseif ~isempty(v.warnings), res = 'WARN'; end
                    rows(k, :) = {st.code, relPath(app, st.jsonFile), res, v.nRecords, v.summary};
                else
                    rows(k, :) = {st.code, relPath(app, st.jsonFile), 'MISSING', 0, 'Not exported yet - run the station'};
                end
            end
            T = cell2table(rows, 'VariableNames', {'Station', 'File', 'Result', 'Records', 'Detail'});
            app.GridTable.Data = T;
            app.styleResultTable(app.GridTable, T.Result);
            if ~isempty(app.MapAx) && isvalid(app.MapAx), app.drawMap(); end   % map colours follow the exports
        end
    end

    % =====================================================================
    methods (Access = private)
        % ------------------------------------------------------- building
        function buildUI(app)
            f = uifigure('Name', 'Songdo Urban Sensing - Team A Integrated Engineering Instrument', ...
                'Position', [40 40 1520 930], 'Visible', 'off');
            f.CloseRequestFcn = @(~, ~) delete(app);
            app.UIFigure = f;
            movegui(f, 'center');
            main = uigridlayout(f, [2 1], 'RowHeight', {64, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0);

            % header
            hdr = uigridlayout(main, [2 4], 'ColumnWidth', {'1x', 210, 210, 120}, 'RowHeight', {30, 22}, ...
                'Padding', [16 6 16 6], 'RowSpacing', 0);
            app.HeaderGrid = hdr;
            t = uilabel(hdr, 'Text', 'SONGDO URBAN SENSING  |  Team A Integrated Engineering Instrument', ...
                'FontSize', 20, 'FontWeight', 'bold', 'FontColor', 'w');
            t.Layout.Row = 1; t.Layout.Column = 1;
            app.StatusLabel = uilabel(hdr, 'Text', 'Ready');
            app.StatusLabel.Layout.Row = 2; app.StatusLabel.Layout.Column = 1;
            b = uibutton(hdr, 'Text', 'Run ALL 5 stations', 'FontWeight', 'bold', ...
                'BackgroundColor', [0.18 0.62 0.36], 'FontColor', 'w', ...
                'Tooltip', 'Unified end-to-end run of every member pipeline', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.runAllStations()));
            b.Layout.Row = [1 2]; b.Layout.Column = 2;
            b = uibutton(hdr, 'Text', 'Run all verification suites', 'FontWeight', 'bold', ...
                'BackgroundColor', app.Accent, 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.runVerificationSuites()));
            b.Layout.Row = [1 2]; b.Layout.Column = 3;
            app.ThemeButton = uibutton(hdr, 'Text', '', 'Tooltip', 'Switch between dark and light interface', ...
                'BackgroundColor', [0.22 0.25 0.32], 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.toggleTheme()));
            app.ThemeButton.Layout.Row = [1 2]; app.ThemeButton.Layout.Column = 4;

            body = uigridlayout(main, [1 2], 'ColumnWidth', {370, '1x'}, 'Padding', [8 8 8 8]);

            % navigation
            nav = uigridlayout(body, [7 1], 'RowHeight', {22, '1x', 32, 32, 32, 32, 32}, 'Padding', [0 0 0 0]);
            uilabel(nav, 'Text', 'Choose a station or a scenario (task / subtask):', 'FontWeight', 'bold');
            app.Tree = uitree(nav, 'SelectionChangedFcn', @(~, e) app.onTreeSelect(e));
            app.buildTree();
            app.RunButton = uibutton(nav, 'Text', 'Run selected task', 'FontWeight', 'bold', ...
                'Tooltip', 'Runs the member''s original pipeline for this station once, then shows the chosen scenario', ...
                'BackgroundColor', app.Accent, 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.runSelected(false)));
            app.RerunButton = uibutton(nav, 'Text', 'Re-run (ignore cached result)', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.runSelected(true)));
            app.FolderButton = uibutton(nav, 'Text', 'Open member source folder', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.openFolder()));
            app.MemberAppButton = uibutton(nav, 'Text', 'Open S3 member live app (SongdoSensorApp)', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.openS3App()));
            uibutton(nav, 'Text', 'Show telemetry exports folder', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.openPath(app.Registry.exportDir)));

            app.Tabs = uitabgroup(body);
            app.TabTask   = uitab(app.Tabs, 'Title', '  Task Runner  ');
            app.TabLive   = uitab(app.Tabs, 'Title', '  Live Instrument  ');
            app.TabVerify = uitab(app.Tabs, 'Title', '  Verification  ');
            app.TabMap    = uitab(app.Tabs, 'Title', '  Station Map & Sensor Grid  ');
            app.TabLog    = uitab(app.Tabs, 'Title', '  Console Log  ');
            app.buildTaskTab();
            app.buildLiveTab();
            app.buildVerifyTab();
            app.buildMapTab();
            app.buildLogTab();
            app.applyTheme();
        end

        function toggleTheme(app)
            if strcmp(app.Theme, 'dark'), app.setTheme('light'); else, app.setTheme('dark'); end
        end

        function applyTheme(app)
            %APPLYTHEME  Colour every hand-styled component for app.Theme.
            p = palette(app.Theme);
            f = app.UIFigure;
            try, theme(f, app.Theme); catch, end   % R2025a+ themes all standard components %#ok<NOCOMMA>
            f.Color = p.bg;
            app.HeaderGrid.BackgroundColor = p.header;
            app.StatusLabel.FontColor = p.status;
            if strcmp(app.Theme, 'dark'), app.ThemeButton.Text = 'Light mode'; else, app.ThemeButton.Text = 'Dark mode'; end
            app.Card.BackgroundColor = p.panel;
            app.ViewPanel.BackgroundColor = p.panel;
            app.TaskTitle.FontColor = p.title;
            app.TaskSpec.FontColor = p.text;
            app.TaskMeta.FontColor = p.muted;
            for k = 1:numel(app.StageLabels)
                set(app.StageLabels(k), 'BackgroundColor', p.stage(k, :), 'FontColor', p.stageText);
            end
            set(app.StartButton, 'BackgroundColor', p.start, 'FontColor', p.btnText);
            set(app.StopButton, 'BackgroundColor', p.stop, 'FontColor', p.btnText);
            set(app.ExportButton, 'BackgroundColor', p.export, 'FontColor', p.btnText);
            app.FeatureLabel.FontColor = p.feature;
            app.LiveState.FontColor = p.title;
            app.SourceLabel.FontColor = p.muted;
            app.VerifyHint.FontColor = p.muted;
            app.RawLine.Color = p.raw;      app.FiltLine.Color = p.filt;
            app.SpecRawLine.Color = p.raw;  app.SpecFiltLine.Color = p.filt;
            app.restyleTables();
            app.drawMap();
        end

        function restyleTables(app)
            d = app.ChecksTable.Data;
            if iscell(d) && size(d, 2) >= 4, app.styleResultTable(app.ChecksTable, d(:, 4)); end
            for tbl = [app.VerifyTable app.GridTable]
                if istable(tbl.Data) && height(tbl.Data) > 0, app.styleResultTable(tbl, tbl.Data.Result); end
            end
        end

        function buildTree(app)
            for st = app.Registry.stations
                sn = uitreenode(app.Tree, 'Text', stationText(st, ''), ...
                    'NodeData', struct('code', st.code, 'task', ''));
                app.NodeByKey(st.code) = sn;
                for tk = st.tasks.'
                    txt = sprintf('%s   %s', tk.id, tk.title);
                    if ~tk.implemented, txt = [txt '   (not implemented)']; end
                    tn = uitreenode(sn, 'Text', txt, 'NodeData', struct('code', st.code, 'task', tk.id));
                    app.NodeByKey(tk.id) = tn;
                end
            end
        end

        function buildTaskTab(app)
            g = uigridlayout(app.TabTask, [3 1], 'RowHeight', {112, '1x', 170}, 'Padding', [10 8 10 8]);
            card = uigridlayout(g, [3 1], 'RowHeight', {28, '1x', '1x'}, ...
                'Padding', [12 6 12 6], 'RowSpacing', 2);
            app.Card = card;
            app.TaskTitle = uilabel(card, 'Text', '', 'FontSize', 18, 'FontWeight', 'bold');
            app.TaskSpec = uilabel(card, 'Text', '', 'WordWrap', 'on', 'FontSize', 13);
            app.TaskMeta = uilabel(card, 'Text', '', 'WordWrap', 'on');

            mid = uigridlayout(g, [1 2], 'ColumnWidth', {'3x', '2x'}, 'Padding', [0 0 0 0]);
            vp = uigridlayout(mid, [2 2], 'RowHeight', {28, '1x'}, 'ColumnWidth', {'1x', 190}, ...
                'Padding', [0 0 0 0]);
            app.ViewPanel = vp;
            app.ViewDrop = uidropdown(vp, 'Items', {'(run the task to see results)'}, ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.showView()));
            app.PopButton = uibutton(vp, 'Text', 'Pop out interactive figure', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.popOut()));
            app.ViewImage = uiimage(vp, 'ScaleMethod', 'fit');
            app.ViewImage.Layout.Row = 2; app.ViewImage.Layout.Column = [1 2];
            app.ViewText = uitextarea(vp, 'Editable', 'off', 'FontName', 'Consolas', 'Visible', 'off');
            app.ViewText.Layout.Row = 2; app.ViewText.Layout.Column = [1 2];

            app.ChecksTable = uitable(mid, 'ColumnName', {'Check', 'Handbook target', 'Measured', 'Result'}, ...
                'ColumnWidth', {'5x', '3x', '4x', 70}, 'RowName', {});
            app.ConsoleArea = uitextarea(g, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
        end

        function buildLiveTab(app)
            g = uigridlayout(app.TabLive, [5 1], 'RowHeight', {62, 34, 22, '1x', 160}, 'Padding', [10 8 10 8], 'RowSpacing', 6);
            strip = uigridlayout(g, [1 13], 'ColumnWidth', repmat({'1x', 14}, 1, 7), 'Padding', [0 0 0 0], 'ColumnSpacing', 2);
            strip.ColumnWidth(end) = [];
            names = {'1 PHENOMENON', '2 TRANSDUCER', '3 ANALOG AAF', '4 ADC', '5 CAUSAL FILTER', '6 FEATURES', '7 TELEMETRY'};
            app.StageLabels = gobjects(1, 7);
            for k = 1:7
                app.StageLabels(k) = uilabel(strip, 'Text', names{k}, 'WordWrap', 'on', ...
                    'HorizontalAlignment', 'center', 'FontSize', 11);
                app.StageLabels(k).Layout.Column = 2*k - 1;
                if k < 7
                    a = uilabel(strip, 'Text', '>', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                    a.Layout.Column = 2*k;
                end
            end

            ctl = uigridlayout(g, [1 12], 'ColumnWidth', {48, 165, 54, 175, 115, 52, 70, 64, 64, 64, 58, '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6);
            uilabel(ctl, 'Text', 'Station', 'HorizontalAlignment', 'right');
            items = arrayfun(@(s) sprintf('%s  %s', s.code, s.name), app.Registry.stations, 'UniformOutput', false);
            app.LiveStation = uidropdown(ctl, 'Items', items, 'ItemsData', {app.Registry.stations.code}, ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.onLiveStationChanged()));
            uilabel(ctl, 'Text', 'Channel', 'HorizontalAlignment', 'right');
            app.LiveChannel = uidropdown(ctl, 'Items', {'-'}, ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.onLiveChannelChanged()));
            app.FsLabel = uilabel(ctl, 'Text', 'Fs = -', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            uilabel(ctl, 'Text', 'fc (Hz)', 'HorizontalAlignment', 'right');
            app.CutoffField = uieditfield(ctl, 'numeric', 'Value', 0, 'Tooltip', 'Live cutoff tuning (Hz), applied at next block, state kept', ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.onCutoffChanged()));
            app.StartButton = uibutton(ctl, 'Text', 'START', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.liveStart()));
            app.StopButton = uibutton(ctl, 'Text', 'STOP', 'FontWeight', 'bold', ...
                'Enable', 'off', 'ButtonPushedFcn', @(~, ~) app.safe(@() app.liveStop()));
            app.ResetButton = uibutton(ctl, 'Text', 'RESET', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.onLiveChannelChanged()));
            uibutton(ctl, 'Text', 'STEP', 'Tooltip', 'Process one block manually', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.liveStep(1)));
            app.ExportButton = uibutton(ctl, 'Text', 'EXPORT JSON', 'Tooltip', 'Write the telemetry buffer as Sensor Grid JSON + CSV (Handbook 5.3)', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.safe(@() app.exportLive()));

            info = uigridlayout(g, [1 3], 'ColumnWidth', {'5x', 230, '3x'}, 'Padding', [0 0 0 0]);
            app.FeatureLabel = uilabel(info, 'Text', '', 'FontWeight', 'bold');
            app.LiveState = uilabel(info, 'Text', '', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            app.SourceLabel = uilabel(info, 'Text', '', 'HorizontalAlignment', 'right', 'FontSize', 11);

            plots = uigridlayout(g, [1 2], 'ColumnWidth', {'5x', '4x'}, 'Padding', [0 0 0 0]);
            app.ScopeAx = uiaxes(plots);
            title(app.ScopeAx, 'Dual-trace oscilloscope  (grey: raw | blue: causal filtered)');
            grid(app.ScopeAx, 'on'); hold(app.ScopeAx, 'on');
            app.RawLine = plot(app.ScopeAx, NaN, NaN, 'LineWidth', 0.8);
            app.FiltLine = plot(app.ScopeAx, NaN, NaN, 'LineWidth', 1.6);
            legend(app.ScopeAx, {'Raw', 'Causal filtered'}, 'Location', 'northwest');
            app.SpecAx = uiaxes(plots);
            title(app.SpecAx, 'Real-time spectrum (one-sided, Hann coherent-gain corrected)');
            grid(app.SpecAx, 'on'); hold(app.SpecAx, 'on');
            app.SpecRawLine = plot(app.SpecAx, NaN, NaN);
            app.SpecFiltLine = plot(app.SpecAx, NaN, NaN, 'LineWidth', 1.3);
            app.NyqLine = xline(app.SpecAx, 1, 'r--', 'Nyquist F_s/2 (filtered)', 'LabelVerticalAlignment', 'bottom');
            xlabel(app.SpecAx, 'Frequency (Hz)'); ylabel(app.SpecAx, 'Amplitude (dB re 1 unit)');
            legend(app.SpecAx, {'Raw', 'Filtered'}, 'Location', 'northeast');

            app.TeleTable = uitable(g, 'ColumnName', {'Timestamp (UTC)', 'Station', 'Channel', 'Raw', 'Filtered', 'Unit', 'Quality'}, ...
                'ColumnWidth', {190, 230, 160, 100, 100, 70, 110}, 'RowName', {});
        end

        function buildVerifyTab(app)
            g = uigridlayout(app.TabVerify, [3 1], 'RowHeight', {30, '6x', '5x'}, 'Padding', [10 8 10 8]);
            row = uigridlayout(g, [1 2], 'ColumnWidth', {280, '1x'}, 'Padding', [0 0 0 0]);
            uibutton(row, 'Text', 'Run all verification suites (~1 min)', 'FontWeight', 'bold', ...
                'BackgroundColor', app.Accent, 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.runVerificationSuites()));
            app.VerifyHint = uilabel(row, 'Text', ['S1 test_S1 | S2 test_S2 | S3 run_all_tests | S4 test_S4 + asserts | ' ...
                'S5 output-based checks | Sensor Grid schema for all stations | registry + Haversine']);
            app.VerifyTable = uitable(g, 'ColumnName', {'Station', 'Suite', 'Result', 'Detail'}, ...
                'ColumnWidth', {70, '2x', 70, '3x'}, 'RowName', {});
            app.VerifyLog = uitextarea(g, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
        end

        function buildMapTab(app)
            g = uigridlayout(app.TabMap, [3 2], 'RowHeight', {28, 28, '1x'}, 'ColumnWidth', {'3x', '2x'}, ...
                'Padding', [10 8 10 8], 'RowSpacing', 4);
            ctl = uigridlayout(g, [1 5], 'ColumnWidth', {58, 150, 38, 330, '1x'}, 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            ctl.Layout.Row = 1; ctl.Layout.Column = 1;
            nv = uigridlayout(g, [1 10], 'ColumnWidth', {58, 34, 34, 34, 34, 34, 34, 100, 90, '1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            nv.Layout.Row = 2; nv.Layout.Column = 1;
            uilabel(nv, 'Text', 'Navigate', 'HorizontalAlignment', 'right');
            uilabel(ctl, 'Text', 'Basemap', 'HorizontalAlignment', 'right');
            app.MapBase = uidropdown(ctl, 'Items', {'Topographic', 'Streets', 'Satellite', 'Offline (no internet)'}, ...
                'ItemsData', {'topographic', 'streets', 'satellite', 'darkwater'}, 'Value', 'topographic', ...
                'Tooltip', 'Street / satellite tiles are downloaded (internet needed); Offline works anywhere', ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.drawMap()));
            uilabel(ctl, 'Text', 'Show', 'HorizontalAlignment', 'right');
            app.MapMode = uidropdown(ctl, 'Items', { ...
                'Overview: stations and sites', ...
                'Overview: latest readings (telemetry JSON)', ...
                'Overview: Sensor Grid conformance (Sec. 5.3)', ...
                'S1 site: 250 m^2 density area, IN/OUT gates', ...
                'S2 site: noise contours from measured Leq', ...
                'S3 site: wind vector + wind history', ...
                'S4 site: CAI air-quality halo', ...
                'S5 site: canal water-level gauge'}, ...
                'ItemsData', {'stations', 'readings', 'grid', 'site:S1', 'site:S2', 'site:S3', 'site:S4', 'site:S5'}, ...
                'ValueChangedFcn', @(~, ~) app.safe(@() app.onMapMode()));
            nav = {char(9664), 'west', 'Pan west'; char(9650), 'north', 'Pan north'; char(9660), 'south', 'Pan south'; ...
                   char(9654), 'east', 'Pan east'; '+', 'in', 'Zoom in'; char(8722), 'out', 'Zoom out'};
            for k = 1:size(nav, 1)
                d = nav{k, 2};
                uibutton(nv, 'Text', nav{k, 1}, 'Tooltip', nav{k, 3}, 'FontWeight', 'bold', ...
                    'ButtonPushedFcn', @(~, ~) app.safe(@() app.mapNav(d)));
            end
            uibutton(nv, 'Text', 'Zoom to site', 'Tooltip', 'Open the site view of the selected station', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.mapNav('site')));
            uibutton(nv, 'Text', 'Reset view', 'ButtonPushedFcn', @(~, ~) app.safe(@() app.resetMapView()));
            uilabel(nv, 'Text', '  or drag to pan, scroll to zoom', 'FontColor', [0.55 0.58 0.64]);
            app.MapAx = geoaxes(g);
            app.MapAx.Layout.Row = 3; app.MapAx.Layout.Column = 1;
            try, enableDefaultInteractivity(app.MapAx); catch, end   % mouse drag = pan, wheel = zoom %#ok<NOCOMMA>

            right = uigridlayout(g, [4 1], 'RowHeight', {'4x', 30, '3x', '2x'}, 'Padding', [0 0 0 0]);
            right.Layout.Row = [1 3]; right.Layout.Column = 2;
            app.MapInfo = uitextarea(right, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
            bar = uigridlayout(right, [1 5], 'ColumnWidth', {'1x', 96, 32, 32, 70}, 'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            app.MapOpenButton = uibutton(bar, 'Text', 'Open in Task Runner', 'FontWeight', 'bold', ...
                'BackgroundColor', app.Accent, 'FontColor', 'w', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.mapClick(app.MapSel)));
            app.PlaceButton = uibutton(bar, 'Text', 'Place site', 'FontWeight', 'bold', ...
                'Tooltip', 'Then click the map where this station''s site overlay should be (e.g. the walkway for the S1 counting area)', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.togglePlacing()));
            app.RotLeftButton = uibutton(bar, 'Text', char(10226), 'FontWeight', 'bold', 'Tooltip', 'Rotate the area 10 deg counter-clockwise', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.rotateSite(app.MapSel, 10)));
            app.RotRightButton = uibutton(bar, 'Text', char(10227), 'FontWeight', 'bold', 'Tooltip', 'Rotate the area 10 deg clockwise', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.rotateSite(app.MapSel, -10)));
            app.ResetSiteButton = uibutton(bar, 'Text', 'Reset site', 'Tooltip', 'Put the overlay back on the handbook station point', ...
                'ButtonPushedFcn', @(~, ~) app.safe(@() app.resetSite(app.MapSel)));
            app.MapHistAx = uiaxes(right);
            app.GridTable = uitable(right, 'ColumnName', {'Station', 'File', 'Result', 'Records', 'Detail'}, ...
                'ColumnWidth', {55, 200, 65, 60, 600}, 'RowName', {});
        end

        function buildLogTab(app)
            g = uigridlayout(app.TabLog, [2 1], 'RowHeight', {30, '1x'}, 'Padding', [10 8 10 8]);
            row = uigridlayout(g, [1 3], 'ColumnWidth', {140, 140, '1x'}, 'Padding', [0 0 0 0]);
            uibutton(row, 'Text', 'Save log...', 'ButtonPushedFcn', @(~, ~) app.safe(@() app.saveLog()));
            uibutton(row, 'Text', 'Clear log', 'ButtonPushedFcn', @(~, ~) app.clearLog());
            app.LogArea = uitextarea(g, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
        end

        % ---------------------------------------------------- task runner
        function onTreeSelect(app, e)
            if isempty(e.SelectedNodes), return; end
            app.safe(@() app.applySelection(e.SelectedNodes(1).NodeData));
        end

        function applySelection(app, sel)
            app.Sel = sel;
            st = app.station(sel.code);
            res = [];
            if app.Cache.isKey(st.code), res = app.Cache(st.code); end
            app.MemberAppButton.Enable = app.onOff(strcmp(st.code, 'S3'));

            if isempty(sel.task)                       % ---- station overview
                app.TaskTitle.Text = sprintf('%s  %s  -  %s   (%s)', st.code, st.name, st.site, st.stationId);
                nImpl = sum([st.tasks.implemented]);
                app.TaskSpec.Text = sprintf(['Location %.4f N, %.4f E, elevation %.1f m.  %d of 5 handbook scenarios implemented ' ...
                    'by the member.  Select a scenario on the left or press "Run selected task" to run the whole station.'], ...
                    st.lat, st.lon, st.elev, nImpl);
                app.TaskMeta.Text = sprintf('Member entry point: %s     |  Folder: %s', st.entry, relPath(app, st.folder));
                app.RunButton.Text = sprintf('Run station %s (all scenarios)', st.code);
                C = cell(0, 4);
                for tk = st.tasks.'
                    Ck = songdoui.taskChecks(st, tk, res, app.Registry);
                    nP = sum(strcmp(Ck(:, 4), 'PASS')); nF = sum(strcmp(Ck(:, 4), 'FAIL'));
                    if ~tk.implemented, r = 'MISSING'; elseif isempty(res), r = 'PENDING';
                    elseif nF > 0, r = 'FAIL'; else, r = 'PASS'; end
                    C(end+1, :) = {sprintf('%s %s', tk.id, tk.title), tk.target, sprintf('%d pass / %d fail', nP, nF), r}; %#ok<AGROW>
                end
                app.setViews(st, [], res);
                app.setConsole(res, '');
            else                                       % ---- one scenario
                tk = st.tasks(strcmp({st.tasks.id}, sel.task));
                app.TaskTitle.Text = sprintf('%s   %s', tk.id, tk.title);
                tgt = tk.target; if isempty(tgt), tgt = '-'; end
                app.TaskSpec.Text = sprintf('Handbook specification:  %s\nTarget / deliverable:  %s', tk.spec, tgt);
                state = 'IMPLEMENTED'; if ~tk.implemented, state = 'NOT IMPLEMENTED in midterm'; end
                app.TaskMeta.Text = sprintf('Status: %s   |   Member code: %s   |   Station %s (%s)', ...
                    state, tk.impl, st.code, st.stationId);
                app.RunButton.Text = sprintf('Run %s', tk.id);
                C = songdoui.taskChecks(st, tk, res, app.Registry);
                app.setViews(st, tk, res);
                app.setConsole(res, tk.id);
            end
            app.ChecksTable.Data = C;
            app.styleResultTable(app.ChecksTable, C(:, 4));
        end

        function runStationNow(app, st, showDialog)
            if nargin < 3, showDialog = true; end
            app.liveStop();
            d = [];
            if showDialog
                d = uiprogressdlg(app.UIFigure, 'Title', sprintf('Running %s %s', st.code, st.name), ...
                    'Message', sprintf('Member entry point:  %s\n(original member code, unchanged)', st.entry), ...
                    'Indeterminate', 'on');
            end
            app.status(sprintf('Running %s ...', st.code)); drawnow;
            if app.Cache.isKey(st.code)                       % release old figures
                old = app.Cache(st.code);
                delete(old.figures(isvalid(old.figures)));
                app.Cache.remove(st.code);
            end
            ck = app.CropCache.keys;
            for k = 1:numel(ck)
                if startsWith(ck{k}, st.code), c = app.CropCache(ck{k}); if isvalid(c), delete(c); end, app.CropCache.remove(ck{k}); end
            end
            res = songdoui.runStation(st);
            app.Cache(st.code) = res;
            app.prerender(st, res, d);
            app.log(sprintf('=== %s %s  (%s, %.1f s, %d figures) ===\n%s', st.code, st.name, ...
                okText(res.ok), res.elapsed, numel(res.figures), res.console));
            node = app.NodeByKey(st.code); node.Text = stationText(st, res);
            if ~isempty(d), close(d); end
            app.status(sprintf('%s finished: %s in %.1f s, %d figures captured', st.code, okText(res.ok), res.elapsed, numel(res.figures)));
            if ~res.ok
                uialert(app.UIFigure, res.error, sprintf('%s failed', st.code));
            end
            app.validateAllExports();
        end

        function prerender(app, st, res, d)
            %PRERENDER  Render every view of a station once, right after it runs,
            %   so switching between its tasks afterwards is instant.
            figs = res.figures(isvalid(res.figures));
            figs = figs(:).';
            for tk = st.tasks.'
                if startsWith(tk.view, 'S5-')
                    f = app.cropAxes(res, tk);
                    if ~isempty(f), figs(end+1) = f; end %#ok<AGROW>
                end
            end
            for k = 1:numel(figs)
                msg = sprintf('Preparing views for fast switching: %d / %d  (%s)', k, numel(figs), figs(k).Name);
                app.status(msg);
                if ~isempty(d) && isvalid(d)
                    d.Indeterminate = 'off'; d.Value = (k - 1)/numel(figs); d.Message = msg;
                end
                drawnow limitrate
                app.figurePng(figs(k));
            end
        end

        function png = figurePng(app, f)
            %FIGUREPNG  Image of a member figure, rendered once and kept with the figure.
            png = '';
            if isappdata(f, 'songdoui_png'), png = getappdata(f, 'songdoui_png'); end
            if isempty(png) || ~isfile(png)
                png = [tempname(app.ViewDir) '.png'];
                exportgraphics(f, png, 'Resolution', 110);
                setappdata(f, 'songdoui_png', png);
            end
        end

        function setViews(app, st, tk, res)
            V = struct('label', {}, 'kind', {}, 'fig', {}, 'png', {}, 'text', {});
            if ~isempty(tk) && ~tk.implemented
                V(end+1) = mkView('Scenario not implemented', 'text', [], '', sprintf([ ...
                    '%s  %s\n\nThis scenario is NOT implemented in the Team A midterm submission.\n\n' ...
                    'Handbook specification:\n  %s\n\nWhen the member adds it, register the figure name in ' ...
                    '+songdoui/registry.m and it appears here automatically.'], tk.id, tk.title, tk.spec));
            elseif isempty(res)
                V(end+1) = mkView('Not run yet', 'text', [], '', sprintf([ ...
                    'Press "Run selected task" (or "Run ALL 5 stations").\n\nThe integrated instrument will execute the ' ...
                    'member''s original entry point:\n\n  %s\n\nHow the member runs it manually:\n\n%s'], st.entry, st.howToRun));
            else
                if isempty(tk)                                     % station: every figure
                    for f = res.figures(:).'
                        if isvalid(f), V(end+1) = mkView(f.Name, 'fig', f, '', ''); end %#ok<AGROW>
                    end
                    if isfile(st.jsonFile), V(end+1) = mkView('Telemetry JSON preview', 'text', [], '', app.jsonPreview(st)); end
                else
                    if startsWith(tk.view, 'S5-')
                        f = app.cropAxes(res, tk);
                        if ~isempty(f), V(end+1) = mkView([tk.id ' | ' f.Name], 'fig', f, '', ''); end
                    end
                    for p = tk.figPatterns
                        if startsWith(tk.view, 'S5-'), break; end
                        for f = res.figures(:).'
                            if isvalid(f) && contains(f.Name, p{1}), V(end+1) = mkView(f.Name, 'fig', f, '', ''); end %#ok<AGROW>
                        end
                    end
                    if strcmp(tk.view, 'json') || isempty(V)
                        if isfile(st.jsonFile)
                            V(end+1) = mkView('Telemetry JSON preview + schema validation', 'text', [], '', app.jsonPreview(st));
                        end
                    end
                    if isempty(V)
                        V(end+1) = mkView('Console output', 'text', [], '', res.console);
                    end
                end
            end
            app.Views = V;
            app.ViewDrop.Items = {V.label};
            app.ViewDrop.ItemsData = 1:numel(V);
            app.ViewDrop.Value = 1;
            app.showView();
        end

        function showView(app)
            if isempty(app.Views), return; end
            k = app.ViewDrop.Value;
            v = app.Views(k);
            isFig = strcmp(v.kind, 'fig');
            app.PopButton.Enable = app.onOff(isFig);
            if isFig
                if isempty(v.png) || ~isfile(v.png)
                    v.png = app.figurePng(v.fig);     % instant if pre-rendered
                    app.Views(k).png = v.png;
                end
                app.ViewImage.ImageSource = v.png;
                app.ViewImage.Visible = 'on'; app.ViewText.Visible = 'off';
            else
                app.ViewText.Value = splitlines(string(v.text));
                app.ViewText.Visible = 'on'; app.ViewImage.Visible = 'off';
            end
        end

        function popOut(app)
            v = app.Views(app.ViewDrop.Value);
            if strcmp(v.kind, 'fig') && isvalid(v.fig)
                v.fig.Visible = 'on';
                figure(v.fig);
            end
        end

        function f = cropAxes(app, res, tk)
            %CROPAXES  One subplot of a multi-panel member figure (S5).
            key = tk.id;
            if app.CropCache.isKey(key) && isvalid(app.CropCache(key)), f = app.CropCache(key); return; end
            f = [];
            for src = res.figures(:).'
                if ~isvalid(src), continue; end
                axs = findobj(src, 'Type', 'axes');
                for ax = axs(:).'
                    if contains(string(ax.Title.String), tk.view)
                        f = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1150 680], ...
                            'Name', char(string(ax.Title.String)), 'HandleVisibility', 'off');
                        f.CloseRequestFcn = @(h, ~) set(h, 'Visible', 'off');
                        try, theme(f, 'light'); catch, end %#ok<NOCOMMA>
                        items = ax; if ~isempty(ax.Legend), items = [ax.Legend ax]; end
                        c = copyobj(items, f);
                        set(c(end), 'Units', 'normalized', 'Position', [0.08 0.11 0.88 0.68]);
                        app.CropCache(key) = f;
                        return
                    end
                end
            end
        end

        function txt = jsonPreview(app, st)
            v = songdoui.validateSensorGrid(st.jsonFile, app.Registry);
            lines = splitlines(string(fileread(st.jsonFile)));
            n = min(numel(lines), 70);
            txt = sprintf('FILE: %s\nSCHEMA (Handbook 5.3): %s\n%s\n%s', st.jsonFile, v.summary, ...
                repmat('-', 1, 90), strjoin(lines(1:n), newline));
            if numel(lines) > n, txt = sprintf('%s\n... (%d more lines)', txt, numel(lines) - n); end
        end

        function setConsole(app, res, id)
            if isempty(res)
                app.ConsoleArea.Value = {'(console output appears here after the run)'};
                return
            end
            txt = res.console;
            if ~isempty(id)
                part = consoleSection(txt, id);
                if strlength(strtrim(part)) > 0
                    txt = sprintf('--- console lines for %s (full output in Console Log tab) ---\n%s', id, part);
                end
            end
            app.ConsoleArea.Value = splitlines(string(txt));
        end

        function openFolder(app)
            app.openPath(app.station(app.Sel.code).folder);
        end

        function openPath(~, p)
            if ~isfolder(p), mkdir(p); end
            if ispc, winopen(p); else, disp(p); end
        end

        function openS3App(app)
            st = app.station('S3');
            for k = 1:numel(st.paths), addpath(st.paths{k}); end
            app.log('Opening S3 member app: SongdoSensorApp()');
            SongdoSensorApp();
        end

        % -------------------------------------------------- live instrument
        function onLiveStationChanged(app)
            app.liveStop();
            chans = songdoui.LiveStream.channels(app.LiveStation.Value);
            app.LiveChannel.Items = chans;
            app.LiveChannel.Value = chans{1};
            app.onLiveChannelChanged();
        end

        function onLiveChannelChanged(app)
            wasRunning = ~isempty(app.LiveTimer);
            app.liveStop();
            app.status(sprintf('Preparing %s / %s stream ...', app.LiveStation.Value, app.LiveChannel.Value)); drawnow;
            app.Stream = songdoui.LiveStream(app.LiveStation.Value, app.LiveChannel.Value);
            s = app.Stream;
            app.RawT = zeros(0, 1); app.RawX = zeros(0, 1); app.FiltT = zeros(0, 1); app.FiltY = zeros(0, 1);
            app.Records = app.Records([]);
            app.StartUtc = datetime('now', 'TimeZone', 'UTC');
            set([app.RawLine app.FiltLine app.SpecRawLine app.SpecFiltLine], 'XData', NaN, 'YData', NaN);
            app.TeleTable.Data = cell(0, 7);
            if s.FsFilt ~= s.FsRaw
                app.FsLabel.Text = sprintf('Fs %s -> %s', fsText(s.FsRaw), fsText(s.FsFilt));
            else
                app.FsLabel.Text = sprintf('Fs = %s', fsText(s.FsRaw));
            end
            app.CutoffField.Enable = app.onOff(s.Tunable);
            if s.Tunable, app.CutoffField.Value = s.Cutoff; else, app.CutoffField.Value = 0; end
            for k = 1:7, app.StageLabels(k).Text = stageText(k, s.Stages{k}); end
            xlabel(app.ScopeAx, sprintf('Time (%s)', s.TimeUnit)); ylabel(app.ScopeAx, s.Unit);
            app.NyqLine.Value = s.FsFilt/2;
            app.SourceLabel.Text = ['Source: ' s.Source];
            app.FeatureLabel.Text = 'Press START (or STEP) to stream';
            app.LiveState.Text = 'Blocks 0';
            app.status('Ready');
            if wasRunning, app.liveStart(); end
        end

        function onCutoffChanged(app)
            if isempty(app.Stream) || ~app.Stream.Tunable, return; end
            try
                app.Stream.setCutoff(app.CutoffField.Value);
                for k = 1:7, app.StageLabels(k).Text = stageText(k, app.Stream.Stages{k}); end
                app.status(sprintf('Cutoff %.4g Hz applied at next block boundary; filter state retained (no reset).', app.Stream.Cutoff));
            catch err
                app.CutoffField.Value = app.Stream.Cutoff;
                uialert(app.UIFigure, err.message, 'Invalid cutoff');
            end
        end

        function onTick(app)
            if app.TickBusy || ~isvalid(app.UIFigure), return; end
            app.TickBusy = true;
            c = onCleanup(@() app.releaseTick());
            try
                app.processBlock(mod(app.Stream.Blocks, 4) == 0);
            catch err
                app.stopTimer();
                app.setLiveButtons(false);
                uialert(app.UIFigure, err.message, 'Live stream stopped');
            end
        end

        function releaseTick(app)
            if isvalid(app), app.TickBusy = false; end
        end

        function processBlock(app, heavyRefresh)
            s = app.Stream;
            [tr, xr, tf, yf, flag, feat] = s.next();
            W = s.WindowSec;
            app.RawT = [app.RawT; tr]; app.RawX = [app.RawX; xr];
            app.FiltT = [app.FiltT; tf]; app.FiltY = [app.FiltY; yf];
            keepR = app.RawT > app.RawT(end) - W; keepF = app.FiltT > app.FiltT(end) - W;
            app.RawT = app.RawT(keepR); app.RawX = app.RawX(keepR);
            app.FiltT = app.FiltT(keepF); app.FiltY = app.FiltY(keepF);
            sc = s.TimeScale;
            [xd, yd] = envelope2(app.RawT*sc, app.RawX, 1200);    % display only; DSP buffers stay full rate
            set(app.RawLine, 'XData', xd, 'YData', yd);
            [xd, yd] = envelope2(app.FiltT*sc, app.FiltY, 1200);
            set(app.FiltLine, 'XData', xd, 'YData', yd);
            if ~isempty(tf)
                xlim(app.ScopeAx, [max(0, tf(end) - W) max(W, tf(end))]*sc);
                st = app.station(s.Code);
                rec = struct('timestamp', isoUtc(app.StartUtc + seconds(tf(end))), 'channel', s.Channel, ...
                    'raw_value', xr(end), 'filtered_value', yf(end), 'unit', s.Unit, 'quality_flag', flag);
                app.Records(end+1) = rec;
                if numel(app.Records) > 20000, app.Records(1) = []; end
                app.LiveState.Text = sprintf('t = %s | Blocks %d | %s', timeText(tf(end)), s.Blocks, flag);
                app.LiveState.FontColor = flagColor(flag, app.Theme);
                app.FeatureLabel.Text = feat;
                if heavyRefresh && mod(s.Blocks, 8) == 0 || numel(app.Records) <= 1
                    n = min(25, numel(app.Records));
                    R = app.Records(end:-1:end-n+1);
                    app.TeleTable.Data = [{R.timestamp}.', repmat({st.stationId}, n, 1), {R.channel}.', ...
                        num2cell(round([R.raw_value].', 4)), num2cell(round([R.filtered_value].', 4)), {R.unit}.', {R.quality_flag}.'];
                    app.mapLive(s, yf(end), flag);
                end
            end
            if heavyRefresh
                [fr, ar] = ampSpectrum(app.RawT, app.RawX);
                [ff, af] = ampSpectrum(app.FiltT, app.FiltY);
                [fr, ar] = envelope2(fr, 20*log10(ar + eps), 1500);
                [ff, af] = envelope2(ff, 20*log10(af + eps), 1500);
                set(app.SpecRawLine, 'XData', fr, 'YData', ar);
                set(app.SpecFiltLine, 'XData', ff, 'YData', af);
                if ~isempty(fr) || ~isempty(ff)
                    xlim(app.SpecAx, [0 max([fr(:); ff(:); s.FsFilt/2])*1.02]);
                end
            end
            drawnow limitrate
        end

        function file = exportLive(app, interactive)
            if nargin < 2, interactive = true; end
            file = '';
            if isempty(app.Records)
                uialert(app.UIFigure, 'Stream some blocks first (START or STEP).', 'Nothing to export', 'Icon', 'info');
                return
            end
            s = app.Stream; st = app.station(s.Code);
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            base = fullfile(app.Registry.exportDir, sprintf('%s_%s_%s', st.code, s.Channel, stamp));
            pkt = struct('schema_version', '1.0', 'generated_at', isoUtc(datetime('now', 'TimeZone', 'UTC')), ...
                'station_id', st.stationId, 'latitude', st.lat, 'longitude', st.lon, 'records', app.Records(:));
            fid = fopen([base '.json'], 'w');
            fwrite(fid, jsonencode(pkt, 'PrettyPrint', true, 'ConvertInfAndNaN', true), 'char'); fclose(fid);
            writetable(struct2table(app.Records(:)), [base '.csv']);
            v = songdoui.validateSensorGrid([base '.json'], app.Registry);
            app.log(sprintf('Live export: %s.json (%d records) -> %s', base, numel(app.Records), v.summary));
            file = [base '.json'];
            if ~interactive, return; end
            uialert(app.UIFigure, sprintf('%d records written to\n%s.json\n%s.csv\n\nSchema check: %s', ...
                numel(app.Records), base, base, v.summary), 'Sensor Grid export', 'Icon', iconFor(v.ok));
        end

        function setLiveButtons(app, running)
            app.StartButton.Enable = app.onOff(~running);
            app.StopButton.Enable = app.onOff(running);
        end

        function stopTimer(app)
            if ~isempty(app.LiveTimer)
                try, stop(app.LiveTimer); delete(app.LiveTimer); catch, end %#ok<NOCOMMA>
                app.LiveTimer = [];
            end
        end

        function onTimerError(app, e)
            app.stopTimer();
            if isvalid(app.UIFigure)
                app.setLiveButtons(false);
                uialert(app.UIFigure, e.Data.message, 'Timer error');
            end
        end

        % ------------------------------------------------------------ map
        function drawMap(app)
            %DRAWMAP  Songdo Sensor Grid on a real basemap (base MATLAB geoaxes).
            gx = app.MapAx; cla(gx); hold(gx, 'on');
            p = palette(app.Theme);
            S = app.Registry.stations;
            bm = app.MapBase.Value;
            if strcmp(bm, 'streets'), bm = ['streets-' app.Theme]; end     % streets-dark / streets-light
            try, geobasemap(gx, bm); catch, geobasemap(gx, 'darkwater'); end %#ok<NOCOMMA>
            showMode = app.MapMode.Value;
            siteMode = startsWith(showMode, 'site:');
            gt = app.GridTable.Data;
            D = songdoui.haversineKm([S.lat], [S.lon]);
            LR = arrayfun(@songdoui.latestReadings, S, 'UniformOutput', false); LR = [LR{:}];

            % distance links from the selected station, labelled in km (overviews only)
            i0 = find(strcmp({S.code}, app.MapSel), 1);
            for j = 1:numel(S)
                if j == i0 || siteMode, continue; end
                geoplot(gx, [S(i0).lat S(j).lat], [S(i0).lon S(j).lon], '--', 'Color', p.title, 'LineWidth', 1.2, 'HitTest', 'off');
                text(gx, (S(i0).lat + S(j).lat)/2, (S(i0).lon + S(j).lon)/2, sprintf('%.2f km', D(i0, j)), ...
                    'FontSize', 9, 'Color', p.text, 'BackgroundColor', p.panel, 'Margin', 1, ...
                    'HorizontalAlignment', 'center', 'Clipping', 'on', 'HitTest', 'off');
            end

            app.MapSiteText = '';
            if siteMode                              % one station's site view; details go to the side panel
                [app.MapSiteExt(i0), app.MapSiteText] = app.drawSite(gx, S(i0), true, p, LR(i0));
            end

            app.MapLabels = gobjects(1, numel(S));
            app.MapLabelBase = cell(1, numel(S));
            legendTxt = '';
            for k = 1:numel(S)
                st = S(k);
                switch showMode
                    case 'readings'
                        Lr = LR(k);
                        col = Lr.color; lbl = sprintf('%s  %s\n%s', st.code, st.name, Lr.headline);
                        legendTxt = 'colour = handbook status of the latest exported value (details on the right)';
                    case 'grid'
                        res = 'MISSING'; nrec = 0;
                        if istable(gt) && height(gt) >= k, res = gt.Result{k}; nrec = gt.Records(k); end
                        col = p.grey; if strcmp(res, 'PASS'), col = p.good; elseif strcmp(res, 'FAIL'), col = p.bad; elseif strcmp(res, 'WARN'), col = p.suspect; end
                        lbl = sprintf('%s  %s\nJSON %s, %d records', st.code, st.name, res, nrec);
                        legendTxt = 'green = export conforms to Handbook 5.3, red = schema errors, grey = not exported';
                    otherwise
                        col = st.color; lbl = sprintf('%s  %s\n%s', st.code, st.name, st.site);
                        legendTxt = 'click a station for details';
                        if siteMode, legendTxt = sprintf('%s site view  (details and history on the right)', S(i0).code); end
                end
                sel = k == i0;
                edge = p.mapEdge; if sel, edge = [1 0.85 0.2]; end
                h = geoscatter(gx, st.lat, st.lon, 220 + 160*sel, col, 'filled', ...
                    'MarkerEdgeColor', edge, 'LineWidth', 1.5 + 1.5*sel);
                h.ButtonDownFcn = @(~, ~) app.safe(@() app.mapSelect(st.code));
                dlon = 0.0011; ha = 'left';
                if strcmp(st.code, 'S2'), dlon = -0.0011; ha = 'right'; end   % S2 / S4 are 0.5 km apart
                app.MapLabelBase{k} = lbl;
                app.MapLabels(k) = text(gx, st.lat, st.lon + dlon, lbl, 'FontSize', 9.5, 'FontWeight', 'bold', ...
                    'Color', p.text, 'BackgroundColor', p.panel, 'EdgeColor', st.color, 'Margin', 2, ...
                    'HorizontalAlignment', ha, 'VerticalAlignment', 'middle', 'Interpreter', 'none', 'Clipping', 'on', 'HitTest', 'off');
            end
            title(gx, 'Songdo Sensor Grid');
            try, subtitle(gx, legendTxt); catch, title(gx, {'Songdo Sensor Grid', legendTxt}); end %#ok<NOCOMMA>
            if ~app.MapLimitsSet, app.resetMapView(); end

            app.updateMapInfo();
            app.drawHistory();
        end

        function resetMapView(app)
            S = app.Registry.stations;
            latL = [min([S.lat]) - 0.004, max([S.lat]) + 0.004];
            lonL = [min([S.lon]) - 0.008, max([S.lon]) + 0.026];      % room for labels right of S4
            geolimits(app.MapAx, latL, lonL);
            try   % the axes toolbar "restore view" returns here
                app.MapAx.InteractionOptions.RestoredLatitudeLimits = latL;
                app.MapAx.InteractionOptions.RestoredLongitudeLimits = lonL;
            catch
            end
            app.MapLimitsSet = true;
        end

        function mapNav(app, dir)
            %MAPNAV  'north' | 'south' | 'east' | 'west' | 'in' | 'out' | 'site'
            [latL, lonL] = geolimits(app.MapAx);
            c = [mean(latL) mean(lonL)]; h = [diff(latL) diff(lonL)]/2;
            switch dir
                case 'north', c(1) = c(1) + h(1)/2;
                case 'south', c(1) = c(1) - h(1)/2;
                case 'east',  c(2) = c(2) + h(2)/2;
                case 'west',  c(2) = c(2) - h(2)/2;
                case 'in',    h = h/2;
                case 'out',   h = h*2;
                case 'site'                       % open + fit the selected station's site view
                    st = app.station(app.MapSel);
                    if ~strcmp(app.MapMode.Value, ['site:' st.code])
                        app.MapMode.Value = ['site:' st.code];
                        app.drawMap();
                    end
                    e = app.MapSiteExt(strcmp({app.Registry.stations.code}, st.code));
                    hm = 1.35*e;                                      % half-height in metres
                    [la, lo] = app.siteCenter(st);
                    c = [(st.lat + la)/2, (st.lon + lo)/2];           % station point and overlay
                    h = [hm/111320, 1.5*hm/(111320*cosd(st.lat))];
            end
            geolimits(app.MapAx, c(1) + [-1 1]*h(1), c(2) + [-1 1]*h(2));
        end

        function [ext, lbl] = drawSite(app, gx, st, sel, p, Lr)
            %DRAWSITE  Station-specific site overlay from the registry geometry and
            %   the member's latest exported values. Text details only when selected.
            g = st.siteGeom; ext = 100; lbl = '';
            if ~isfield(g, 'kind'), return; end
            st0 = st;                                   % handbook station point (unchanged)
            [st.lat, st.lon, hd] = app.siteCenter(st0);  % overlay centre (placed or station point)
            if isfield(g, 'headingDeg'), g.headingDeg = hd; end
            off = 1000*songdoui.haversineKm([st0.lat st.lat], [st0.lon st.lon]); off = off(1, 2);
            if off > 1                                  % show where the overlay sits relative to the station
                geoplot(gx, [st0.lat st.lat], [st0.lon st.lon], ':', 'Color', p.muted, 'LineWidth', 1.5, 'HitTest', 'off');
                geoscatter(gx, st.lat, st.lon, 30, p.text, '+', 'LineWidth', 1.5, 'HitTest', 'off');
            end
            val = @(ch) mapValue(Lr, ch);
            lw = 1.6 + 0.8*sel;
            col = st.color;
            lbl = ''; lblAt = [st.lat st.lon];
            th = linspace(0, 360, 97);
            switch g.kind
                case 'area'                                   % S1: 250 m^2 density area + gates
                    a = g.headingDeg;
                    R = [cosd(a) sind(a); -sind(a) cosd(a)];
                    xy = ([-1 -1; 1 -1; 1 1; -1 1; -1 -1] .* [g.lengthM g.widthM]/2)*R;
                    n = val('PED_PIR_COUNT'); dens = n/g.areaM2;
                    c = p.good; if dens > 2.5, c = p.bad; elseif dens > 2.0, c = p.suspect; end
                    [la, lo] = offsetM(st.lat, st.lon, xy(:, 1), xy(:, 2));
                    geoplot(gx, la, lo, '-', 'Color', c, 'LineWidth', lw + 1, 'HitTest', 'off');
                    for t = linspace(-0.8, 0.8, 7)            % hatching (filled polygons need Mapping Toolbox)
                        hxy = [t*g.lengthM/2*[1; 1], [-1; 1]*g.widthM/2]*R;
                        [la, lo] = offsetM(st.lat, st.lon, hxy(:, 1), hxy(:, 2));
                        geoplot(gx, la, lo, ':', 'Color', c, 'LineWidth', 1, 'HitTest', 'off');
                    end
                    gxy = [-g.lengthM/2 0; g.lengthM/2 0]*R;  % entry / exit gates on the short sides
                    [la, lo] = offsetM(st.lat, st.lon, gxy(:, 1), gxy(:, 2));
                    geoscatter(gx, la(1), lo(1), 70, p.good, '>', 'filled', 'HitTest', 'off');
                    geoscatter(gx, la(2), lo(2), 70, p.bad, '>', 'filled', 'HitTest', 'off');
                    if sel
                        siteText(gx, la(1), lo(1), 'IN  ', 'right', p);
                        siteText(gx, la(2), lo(2), '  OUT', 'left', p);
                    end
                    lbl = sprintf(['%s\nnet occupancy %s people  ->  density %.2f people/m^2  (alarm > 2.5)\n' ...
                        'IN / OUT gates: bidirectional footstep counting (S1-3)'], g.note, num2str(n), dens);
                    [lblAt(1), lblAt(2)] = offsetM(st.lat, st.lon, 0, -g.widthM/2 - 4);
                    ext = 0.75*g.lengthM;
                case 'acoustic'                               % S2: estimated noise contours
                    Leq = val('LEQ_1S_DBA'); siren = val('EVENT_SIREN_FLAG') > 0;
                    c = col; if siren, c = p.bad; end
                    rs = g.refDistM*10.^((Leq - g.contoursDBA)/20);
                    for k = 1:numel(rs)
                        [la, lo] = offsetM(st.lat, st.lon, rs(k)*sind(th), rs(k)*cosd(th));
                        geoplot(gx, la, lo, '--', 'Color', c, 'LineWidth', max(lw - 0.4*(k - 1), 0.8), 'HitTest', 'off');
                        if sel, siteText(gx, la(1), lo(1), sprintf('%g dBA (%.0f m)', g.contoursDBA(k), rs(k)), 'center', p); end
                    end
                    [la, lo] = offsetM(st.lat, st.lon, g.refDistM*sind(th), g.refDistM*cosd(th));
                    geoplot(gx, la, lo, '-', 'Color', c, 'LineWidth', lw + 0.6, 'HitTest', 'off');
                    sirenTxt = 'no siren'; if siren, sirenTxt = 'SIREN DETECTED (S2-4)'; end
                    lbl = sprintf('%s\nmeasured Leq,1s %.1f dBA at %.1f m (inner ring) | %s', g.note, Leq, g.refDistM, sirenTxt);
                    [lblAt(1), lblAt(2)] = offsetM(st.lat, st.lon, 0, -rs(end) - 6);
                    ext = 1.1*rs(end);
                case 'wind'                                   % S3: downwind arrow + compass ring
                    spd = val('WIND_SPEED_MPS'); from = val('WIND_DIR_DEG');
                    L = max(spd, 0.5)*g.metersPerMps; b = from + 180;      % arrow points downwind
                    rr = 1.25*L;
                    H = songdoui.channelSeries(st, {'WIND_SPEED_MPS', 'WIND_DIR_DEG'});
                    nHist = 0;
                    if H.isKey('WIND_SPEED_MPS') && H.isKey('WIND_DIR_DEG')
                        hs = H('WIND_SPEED_MPS').v; hd = H('WIND_DIR_DEG').v;
                        nHist = min(numel(hs), numel(hd));
                        for k = 1:nHist                   % thin arrows: every exported record
                            Lk = max(hs(k), 0.2)*g.metersPerMps; bk = hd(k) + 180;
                            [la, lo] = offsetM(st.lat, st.lon, [0 Lk*sind(bk)], [0 Lk*cosd(bk)]);
                            geoplot(gx, la, lo, '-', 'Color', p.muted, 'LineWidth', 0.9, 'HitTest', 'off');
                        end
                        rr = max(rr, 1.1*max(hs)*g.metersPerMps);
                    end
                    [la, lo] = offsetM(st.lat, st.lon, rr*sind(th), rr*cosd(th));
                    geoplot(gx, la, lo, ':', 'Color', col, 'LineWidth', 1.2, 'HitTest', 'off');
                    [la, lo] = offsetM(st.lat, st.lon, [0 L*sind(b)], [0 L*cosd(b)]);
                    geoplot(gx, la, lo, '-', 'Color', col, 'LineWidth', lw + 1.4, 'HitTest', 'off');
                    for sg = [-1 1]                           % arrow head
                        hb = b + 180 + sg*28;
                        [la2, lo2] = offsetM(la(2), lo(2), [0 0.3*L*sind(hb)], [0 0.3*L*cosd(hb)]);
                        geoplot(gx, la2, lo2, '-', 'Color', col, 'LineWidth', lw + 1.4, 'HitTest', 'off');
                    end
                    if sel
                        cards = {'N', 0; 'E', 90; 'S', 180; 'W', 270};
                        for k = 1:4
                            [la, lo] = offsetM(st.lat, st.lon, rr*sind(cards{k, 2}), rr*cosd(cards{k, 2}));
                            siteText(gx, la, lo, cards{k, 1}, 'center', p);
                        end
                    end
                    lbl = sprintf(['%s\nlatest wind %.2f m/s from %03.0f deg (%s) - thick arrow, points downwind' ...
                        ' | grey arrows: all %d exported wind records | air %.1f degC | RH %.1f %% [%s]'], g.note, spd, from, ...
                        compass(from), nHist, val('AIR_TEMP_C'), val('REL_HUMIDITY_PCT'), mapFlag(Lr, 'REL_HUMIDITY_PCT'));
                    [lblAt(1), lblAt(2)] = offsetM(st.lat, st.lon, 0, -rr - 6);
                    ext = 1.1*rr;
                case 'air'                                    % S4: CAI halo
                    c = Lr.color;
                    for f = [1 0.66 0.33]
                        [la, lo] = offsetM(st.lat, st.lon, f*g.radiusM*sind(th), f*g.radiusM*cosd(th));
                        geoplot(gx, la, lo, '-', 'Color', c, 'LineWidth', lw + 1.6*(1 - f), 'HitTest', 'off');
                    end
                    lbl = sprintf('%s\nCAI %s (%s) | PM2.5 %.1f | PM10 %.1f ug/m3 | CO2 %.0f ppm', g.note, ...
                        num2str(val('AQI_CAI_LEVEL')), Lr.grade, val('PM25_UG_M3'), val('PM10_UG_M3'), val('CO2_NDIR_PPM'));
                    [lblAt(1), lblAt(2)] = offsetM(st.lat, st.lon, 0, -g.radiusM - 6);
                    ext = 1.1*g.radiusM;
                case 'gauge'                                  % S5: staff gauge filled to level
                    lev = val('WATER_LEVEL_M'); H = g.maxM*g.metersPerM; w = 10; x0 = 25;
                    hl = min(max(lev, 0), g.maxM)*g.metersPerM;
                    for y = linspace(0, hl, max(2, round(hl/1.5)))  % water fill as dense lines
                        [la, lo] = offsetM(st.lat, st.lon, x0 + [0 w], -H/2 + [y y]);
                        geoplot(gx, la, lo, '-', 'Color', [0.2 0.55 1], 'LineWidth', 2.5, 'HitTest', 'off');
                    end
                    [la, lo] = offsetM(st.lat, st.lon, x0 + [0 w w 0 0], -H/2 + [0 0 H H 0]);
                    geoplot(gx, la, lo, '-', 'Color', p.text, 'LineWidth', lw, 'HitTest', 'off');
                    for m = 0:g.maxM
                        [la, lo] = offsetM(st.lat, st.lon, x0 + [w w + 4], -H/2 + m*g.metersPerM*[1 1]);
                        geoplot(gx, la, lo, '-', 'Color', p.text, 'LineWidth', 1, 'HitTest', 'off');
                        if sel, siteText(gx, la(2), lo(2), sprintf(' %d m', m), 'left', p); end
                    end
                    lbl = sprintf('%s\nwater level %.2f m  [%s] | MEIS limits: turbidity < 15 NTU, salinity 26-32 PSU', ...
                        g.note, lev, mapFlag(Lr, 'WATER_LEVEL_M'));
                    [lblAt(1), lblAt(2)] = offsetM(st.lat, st.lon, 0, -H/2 - 6);
                    ext = 0.6*H + 20;
            end
            lbl = strrep(lbl, ' | ', newline);   % shown in the side panel, one fact per line
            ext = max(ext, 0.5*off + ext);             % zoom keeps station point and overlay in view
        end

        function [la, lo, hd] = siteCenter(app, st)
            %SITECENTER  Overlay centre and heading: user placement, else the station point.
            la = st.lat; lo = st.lon; hd = NaN;
            if isfield(st.siteGeom, 'headingDeg'), hd = st.siteGeom.headingDeg; end
            if ~isempty(app.Placement) && app.Placement.isKey(st.code)
                v = app.Placement(st.code);
                la = v.lat; lo = v.lon;
                if ~isnan(v.headingDeg), hd = v.headingDeg; end
            end
        end

        function togglePlacing(app)
            %TOGGLEPLACING  Arm / cancel "click on the map to place this station's site".
            if app.PlacingSite
                app.endPlacing();
                app.status('Placement cancelled');
                return
            end
            if ~strcmp(app.MapMode.Value, ['site:' app.MapSel]), app.mapNav('site'); end
            app.PlacingSite = true;
            app.MapAx.ButtonDownFcn = @(~, ~) app.safe(@() app.onPlaceClick());
            p = palette(app.Theme);
            set(app.PlaceButton, 'Text', 'Click map...', 'BackgroundColor', p.suspect, 'FontColor', [0.1 0.1 0.1]);
            app.status(sprintf('Click on the map where the %s site overlay should be (press the button again to cancel)', app.MapSel));
        end

        function onPlaceClick(app)
            cp = app.MapAx.CurrentPoint;                 % geoaxes: [lat lon]
            lat = cp(1, 1); lon = cp(1, 2);
            app.endPlacing();
            app.placeSite(app.MapSel, lat, lon);
            app.status(sprintf('%s site overlay placed at %.6f N, %.6f E (saved to site_placement.json)', app.MapSel, lat, lon));
        end

        function endPlacing(app)
            app.PlacingSite = false;
            app.MapAx.ButtonDownFcn = '';
            try, enableDefaultInteractivity(app.MapAx); catch, end %#ok<NOCOMMA>
            set(app.PlaceButton, 'Text', 'Place site', 'BackgroundColor', [0.96 0.96 0.96], 'FontColor', [0.1 0.1 0.1]);
            try, app.PlaceButton.BackgroundColor = app.RerunButton.BackgroundColor; app.PlaceButton.FontColor = app.RerunButton.FontColor; catch, end %#ok<NOCOMMA>
        end

        function mapSelect(app, code)
            %MAPSELECT  Click on a station marker: highlight it, show details and history.
            %   In a site view, clicking another station opens that station's site view.
            app.MapSel = code;
            if startsWith(app.MapMode.Value, 'site:')
                app.MapMode.Value = ['site:' code];
                app.drawMap();
                app.mapNav('site');
            else
                app.drawMap();
            end
        end

        function onMapMode(app)
            v = app.MapMode.Value;
            if startsWith(v, 'site:')
                app.MapSel = v(6:end);
                app.drawMap();
                app.mapNav('site');
            else
                app.drawMap();
                app.resetMapView();
            end
        end

        function drawHistory(app)
            %DRAWHISTORY  Selected station's handbook channel over time (telemetry JSON).
            ax = app.MapHistAx; cla(ax, 'reset'); hold(ax, 'on'); grid(ax, 'on');
            st = app.station(app.MapSel); p = palette(app.Theme);
            ax.FontSize = 9;
            note = '';
            switch st.code
                case 'S1'
                    H = songdoui.channelSeries(st, {'PED_PIR_COUNT'});
                    if H.isKey('PED_PIR_COUNT')
                        h = H('PED_PIR_COUNT'); a = st.siteGeom.areaM2;
                        plot(ax, h.t, h.v, '-', 'Color', st.color, 'LineWidth', 1.6);
                        yline(ax, 2.5*a, '--', sprintf('alarm 2.5 p/m^2 = %d people', 2.5*a), 'Color', p.bad, 'LabelHorizontalAlignment', 'left');
                        ylabel(ax, 'net occupancy (people)');
                        note = sprintf('%d records', numel(h.v));
                    end
                case 'S2'
                    H = songdoui.channelSeries(st, {'LEQ_1S_DBA', 'SPL_DBA_100MS', 'EVENT_SIREN_FLAG'});
                    if H.isKey('SPL_DBA_100MS'), h = H('SPL_DBA_100MS'); plot(ax, h.t, h.v, '-', 'Color', p.raw, 'LineWidth', 0.8); end
                    if H.isKey('LEQ_1S_DBA'), h = H('LEQ_1S_DBA'); plot(ax, h.t, h.v, '-', 'Color', st.color, 'LineWidth', 1.8); note = sprintf('%d Leq records', numel(h.v)); end
                    yline(ax, 68, '--', 'NoiseLab daytime 68 dBA', 'Color', p.suspect, 'LabelHorizontalAlignment', 'left');
                    if H.isKey('EVENT_SIREN_FLAG')
                        h = H('EVENT_SIREN_FLAG'); on = h.v > 0;
                        if any(on), yl = ylim(ax); scatter(ax, h.t(on), repmat(yl(2), nnz(on), 1), 30, p.bad, 'v', 'filled'); end
                        note = sprintf('%s, %d siren samples', note, nnz(on));
                    end
                    ylabel(ax, 'dBA'); legend(ax, {'SPL 100 ms', 'Leq 1 s'}, 'Location', 'southwest', 'FontSize', 8);
                case 'S3'
                    H = songdoui.channelSeries(st, {'AIR_TEMP_C', 'WIND_SPEED_MPS'});
                    yyaxis(ax, 'left');
                    if H.isKey('AIR_TEMP_C'), h = H('AIR_TEMP_C'); plot(ax, h.t, h.v, '-o', 'Color', st.color, 'LineWidth', 1.6, 'MarkerSize', 4); note = sprintf('%d records', numel(h.v)); end
                    ylabel(ax, 'air temperature (degC)'); ax.YColor = st.color;
                    yyaxis(ax, 'right');
                    if H.isKey('WIND_SPEED_MPS'), h = H('WIND_SPEED_MPS'); plot(ax, h.t, h.v, '-s', 'Color', p.filt, 'LineWidth', 1.2, 'MarkerSize', 4); end
                    ylabel(ax, 'wind speed (m/s)'); ax.YColor = p.filt;
                case 'S4'
                    H = songdoui.channelSeries(st, {'AQI_CAI_LEVEL'});
                    if H.isKey('AQI_CAI_LEVEL')
                        h = H('AQI_CAI_LEVEL');
                        bands = [0 50; 50 100; 100 250; 250 500];
                        bc = [0.20 0.50 1.00; 0.25 0.75 0.35; 1.00 0.65 0.15; 0.90 0.25 0.25];
                        top = max(120, 1.15*max(h.v));
                        for k = 1:4
                            if bands(k, 1) >= top, break; end
                            patch(ax, [h.t(1) h.t(end) h.t(end) h.t(1)], [bands(k, 1) bands(k, 1) min(bands(k, 2), top)*[1 1]], ...
                                bc(k, :), 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HitTest', 'off');
                        end
                        plot(ax, h.t, h.v, '-', 'Color', p.text, 'LineWidth', 1.5);
                        ylim(ax, [0 top]);
                        ylabel(ax, 'CAI'); note = sprintf('%d hourly records; bands: Good / Moderate / Unhealthy / Very Unhealthy', numel(h.v));
                    end
                case 'S5'
                    H = songdoui.channelSeries(st, {'WATER_LEVEL_M'});
                    if H.isKey('WATER_LEVEL_M')
                        h = H('WATER_LEVEL_M');
                        plot(ax, h.t, h.v, '-o', 'Color', st.color, 'LineWidth', 1.6, 'MarkerSize', 5, 'MarkerFaceColor', st.color);
                        ylabel(ax, 'water level (m)'); note = sprintf('%d records', numel(h.v));
                    end
            end
            title(ax, sprintf('%s history from telemetry JSON', st.code), 'FontWeight', 'normal', 'FontSize', 10);
            if ~isempty(note), subtitle(ax, note, 'FontSize', 8); end
        end

        function updateMapInfo(app)
            st = app.station(app.MapSel);
            S = app.Registry.stations;
            L = {};
            if ~isempty(app.MapSiteText)
                L = [{'SITE VIEW'}, cellstr(splitlines(string(app.MapSiteText))).', {app.placementText(st)}, {''}];
            end
            L = [L, {sprintf('%s  %s', st.code, upper(st.name)), st.site, st.stationId, ...
                sprintf('WGS84 %.4f N, %.4f E, elevation %.1f m', st.lat, st.lon, st.elev), ''}];
            if app.Cache.isKey(st.code)
                r = app.Cache(st.code);
                L{end+1} = sprintf('Pipeline (this session): %s in %.1f s, %d figures', okText(r.ok), r.elapsed, numel(r.figures));
            else
                L{end+1} = 'Pipeline: not run in this session (press Run)';
            end
            gt = app.GridTable.Data;
            if istable(gt)
                row = gt(strcmp(gt.Station, st.code), :);
                if height(row), L{end+1} = sprintf('Telemetry export: %s (%d records)', row.Result{1}, row.Records(1)); end
            end
            Lr = songdoui.latestReadings(st);
            L{end+1} = '';
            if Lr.ok
                L{end+1} = sprintf('Latest exported readings  (%s):', Lr.time);
                L = [L, strcat({'  '}, Lr.lines)];
                L{end+1} = ['  map colour: ' Lr.legend];
            else
                L{end+1} = ['Latest readings: ' Lr.headline];
            end
            L{end+1} = '';
            L{end+1} = 'Distance to other stations (Haversine):';
            D = songdoui.haversineKm([S.lat], [S.lon]);
            i0 = find(strcmp({S.code}, st.code), 1);
            for j = 1:numel(S)
                if j ~= i0, L{end+1} = sprintf('  %s %-22s %6.3f km', S(j).code, S(j).name, D(i0, j)); end %#ok<AGROW>
            end
            L{end+1} = '';
            L{end+1} = 'Scenarios:';
            for tk = st.tasks.'
                L{end+1} = sprintf('  %s  %s', tk.id, tk.title); %#ok<AGROW>
            end
            app.MapInfo.Value = L(:);
            app.MapOpenButton.Text = sprintf('Open %s in Task Runner', st.code);
            hasArea = isfield(st.siteGeom, 'kind') && strcmp(st.siteGeom.kind, 'area');
            app.RotLeftButton.Enable = app.onOff(hasArea);
            app.RotRightButton.Enable = app.onOff(hasArea);
            app.ResetSiteButton.Enable = app.onOff(app.Placement.isKey(st.code));
            app.PlaceButton.Tooltip = sprintf('Then click the map where the %s site overlay should be', st.code);
        end

        function t = placementText(app, st)
            [la, lo, hd] = app.siteCenter(st);
            if app.Placement.isKey(st.code)
                d = 1000*songdoui.haversineKm([st.lat la], [st.lon lo]);
                t = sprintf('placement: set by team at %.6f N, %.6f E, %.0f m from the handbook point', la, lo, d(1, 2));
                if ~isnan(hd), t = sprintf('%s, rotation %.0f deg', t, hd); end
                t = [t ' (site_placement.json)'];
            else
                t = 'placement: centred on the handbook station point (use "Place site" to move it)';
            end
        end

        function mapLive(app, s, val, flag)
            %MAPLIVE  Show the Live Instrument's current value on the map label.
            k = find(strcmp({app.Registry.stations.code}, s.Code), 1);
            if isempty(k) || numel(app.MapLabels) < k || ~isvalid(app.MapLabels(k)), return; end
            app.MapLabels(k).String = sprintf('%s\nLIVE %s = %s %s [%s]', app.MapLabelBase{k}, ...
                s.Channel, num2str(val, 4), s.Unit, flag);
        end

        function mapClick(app, code)
            app.selectNode(code);
            app.Tabs.SelectedTab = app.TabTask;
        end

        % ------------------------------------------------------- helpers
        function st = station(app, code)
            S = app.Registry.stations;
            st = S(strcmp({S.code}, code));
        end

        function styleResultTable(app, tbl, results)
            removeStyle(tbl);
            results = cellstr(results);
            p = palette(app.Theme);
            map = {'PASS', p.pass; 'FAIL', p.fail; 'WARN', p.warn; 'MISSING', p.grey; 'PENDING', p.grey};
            for k = 1:size(map, 1)
                r = find(strcmp(results, map{k, 1}));
                if ~isempty(r), addStyle(tbl, uistyle('BackgroundColor', map{k, 2}, 'FontColor', p.rowText), 'row', r); end
            end
        end

        function summaryAlert(app)
            lines = {};
            for st = app.Registry.stations
                if ~app.Cache.isKey(st.code), lines{end+1} = sprintf('%s  not run', st.code); continue; end %#ok<AGROW>
                res = app.Cache(st.code); nP = 0; nF = 0;
                for tk = st.tasks.'
                    C = songdoui.taskChecks(st, tk, res, app.Registry);
                    nP = nP + sum(strcmp(C(:, 4), 'PASS')); nF = nF + sum(strcmp(C(:, 4), 'FAIL'));
                end
                lines{end+1} = sprintf('%s  %-22s %s  %5.1f s   checks: %d pass / %d fail', st.code, st.name, ...
                    okText(res.ok), res.elapsed, nP, nF); %#ok<AGROW>
            end
            app.log(['=== Unified run summary ===' newline strjoin(lines, newline)]);
            uialert(app.UIFigure, strjoin(lines, newline), 'Unified run complete', 'Icon', 'success');
        end

        function status(app, msg)
            if isvalid(app.StatusLabel), app.StatusLabel.Text = msg; end
        end

        function log(app, msg)
            stamp = char(datetime('now', 'Format', 'HH:mm:ss'));
            app.LogText = [app.LogText sprintf('[%s] %s\n', stamp, msg)];
            if ~isempty(app.LogArea) && isvalid(app.LogArea)
                app.LogArea.Value = splitlines(string(app.LogText));
                scroll(app.LogArea, 'bottom');
            end
        end

        function clearLog(app)
            app.LogText = ''; app.LogArea.Value = {''};
        end

        function saveLog(app)
            [f, p] = uiputfile('songdo_integrated_log.txt', 'Save console log');
            if isequal(f, 0), return; end
            fid = fopen(fullfile(p, f), 'w'); fwrite(fid, app.LogText, 'char'); fclose(fid);
        end

        function p = relPath(app, p)
            p = strrep(p, [app.Registry.groupRoot filesep], '');
        end

        function v = onOff(~, tf)
            if tf, v = 'on'; else, v = 'off'; end
        end

        function safe(app, fn)
            %SAFE  Run a UI callback; show errors in a dialog instead of the console.
            try
                fn();
            catch err
                app.log(['ERROR: ' getReport(err, 'extended', 'hyperlinks', 'off')]);
                if isvalid(app.UIFigure)
                    uialert(app.UIFigure, err.message, 'Error');
                end
            end
        end
    end
end

% =========================================================================
function v = mkView(label, kind, fig, png, text)
v = struct('label', label, 'kind', kind, 'fig', fig, 'png', png, 'text', text);
end

function setProgress(d, v, msg)
d.Value = v; d.Message = msg; drawnow;
end

function t = stationText(st, res)
t = sprintf('%s   %s  -  %s', st.code, st.name, st.site);
if ~isempty(res)
    if res.ok, mark = char(10004); else, mark = char(10008); end
    t = sprintf('%s   [%s %.0f s]', t, mark, res.elapsed);
end
end

function s = okText(ok)
if ok, s = 'OK'; else, s = 'FAILED'; end
end

function part = consoleSection(txt, id)
%CONSOLESECTION  Lines that belong to one scenario tag (e.g. '[S2-3]').
lines = splitlines(string(txt));
code = extractBefore(string(id), '-');
cur = ""; keep = false(size(lines));
for k = 1:numel(lines)
    tags = regexp(lines(k), [char(code) '-\d'], 'match');
    if ~isempty(tags), cur = tags(1); end
    keep(k) = cur == id;
end
part = strjoin(lines(keep), newline);
end

function s = stageText(k, value)
names = {'1 PHENOMENON', '2 TRANSDUCER', '3 ANALOG AAF', '4 ADC', '5 CAUSAL FILTER', '6 FEATURES', '7 TELEMETRY'};
s = sprintf('%s\n%s', names{k}, value);
end

function s = fsText(fs)
if fs >= 1000, s = sprintf('%g kHz', fs/1000);
elseif fs >= 1, s = sprintf('%g Hz', fs);
else, s = sprintf('1/%g s', round(1/fs)); end
end

function s = timeText(t)
if t < 120, s = sprintf('%.2f s', t);
elseif t < 7200, s = sprintf('%.1f min', t/60);
else, s = sprintf('%.2f h', t/3600); end
end

function s = isoUtc(dt)
dt.TimeZone = 'UTC';
s = char(dt, 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''');
end

function c = flagColor(flag, mode)
p = palette(mode);
switch flag
    case 'GOOD', c = p.good;
    case 'SUSPECT_JUMP', c = p.suspect;
    otherwise, c = p.bad;
end
end

function [la, lo] = offsetM(lat0, lon0, east, north)
%OFFSETM  Local east/north offsets in metres -> latitude/longitude (small-area approx.).
la = lat0 + north/111320;
lo = lon0 + east./(111320*cosd(lat0));
end

function v = mapValue(Lr, ch)
v = NaN;
if Lr.ok && Lr.value.isKey(ch), v = Lr.value(ch); end
end

function f = mapFlag(Lr, ch)
f = 'n/a';
if Lr.ok && Lr.flag.isKey(ch), f = Lr.flag(ch); end
end

function c = compass(deg)
names = {'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'};
c = names{mod(round(deg/45), 8) + 1};
end

function siteText(gx, la, lo, str, ha, p)
text(gx, la, lo, str, 'FontSize', 8.5, 'FontWeight', 'bold', 'Color', p.text, 'BackgroundColor', p.panel, ...
    'Margin', 1, 'Interpreter', 'none', 'HorizontalAlignment', ha, 'Clipping', 'on', 'HitTest', 'off');
end

function p = palette(mode)
%PALETTE  Colours for the hand-styled parts of the UI (standard components
%   follow theme()). Member figures are not recoloured.
if strcmp(mode, 'dark')
    p.bg = [0.10 0.11 0.13];  p.panel = [0.15 0.16 0.19];  p.header = [0.04 0.08 0.17];
    p.text = [0.92 0.93 0.95]; p.muted = [0.62 0.66 0.72]; p.title = [0.47 0.75 1.00];
    p.status = [0.70 0.84 1.00];
    p.stage = [0.14 0.24 0.36; 0.14 0.24 0.36; 0.24 0.20 0.38; 0.24 0.20 0.38; ...
               0.12 0.30 0.21; 0.12 0.30 0.21; 0.36 0.27 0.11];
    p.stageText = [0.93 0.95 0.98];
    p.start = [0.16 0.45 0.25]; p.stop = [0.58 0.18 0.18]; p.export = [0.14 0.38 0.62]; p.btnText = [1 1 1];
    p.feature = [0.45 0.87 0.56];
    p.pass = [0.12 0.31 0.18]; p.fail = [0.47 0.14 0.14]; p.warn = [0.42 0.33 0.08]; p.grey = [0.24 0.25 0.28];
    p.rowText = [0.95 0.95 0.96];
    p.good = [0.42 0.88 0.52]; p.suspect = [1.00 0.72 0.30]; p.bad = [1.00 0.45 0.45];
    p.raw = [0.55 0.57 0.62]; p.filt = [0.30 0.66 1.00];
    p.mapLink = [0.32 0.34 0.40]; p.mapEdge = [0.95 0.95 0.95];
else
    p.bg = [0.96 0.97 0.98];  p.panel = [1 1 1];  p.header = [0.06 0.16 0.33];
    p.text = [0.12 0.12 0.15]; p.muted = [0.35 0.35 0.40]; p.title = [0.06 0.16 0.33];
    p.status = [0.75 0.88 1.00];
    p.stage = [0.86 0.92 0.98; 0.86 0.92 0.98; 0.90 0.88 0.98; 0.90 0.88 0.98; ...
               0.84 0.95 0.88; 0.84 0.95 0.88; 1.00 0.93 0.82];
    p.stageText = [0.10 0.10 0.15];
    p.start = [0.80 0.94 0.82]; p.stop = [0.98 0.82 0.82]; p.export = [0.85 0.92 1.00]; p.btnText = [0.10 0.10 0.15];
    p.feature = [0.10 0.40 0.15];
    p.pass = [0.80 0.94 0.82]; p.fail = [0.98 0.80 0.80]; p.warn = [1.00 0.93 0.75]; p.grey = [0.92 0.92 0.92];
    p.rowText = [0.10 0.10 0.12];
    p.good = [0.10 0.50 0.20]; p.suspect = [0.80 0.50 0.00]; p.bad = [0.80 0.10 0.10];
    p.raw = [0.60 0.60 0.60]; p.filt = [0.05 0.35 0.85];
    p.mapLink = [0.80 0.80 0.85]; p.mapEdge = [0 0 0];
end
end

function i = iconFor(ok)
if ok, i = 'success'; else, i = 'warning'; end
end

function [xo, yo] = envelope2(x, y, nMax)
%ENVELOPE2  Min/max decimation for DISPLAY: keeps peaks, caps point count.
n = numel(y);
if n <= nMax, xo = x; yo = y; return; end
nb = floor(nMax/2); L = floor(n/nb); m = nb*L;
Y = reshape(y(1:m), L, nb); X = reshape(x(1:m), L, nb);
[ymin, imin] = min(Y, [], 1); [ymax, imax] = max(Y, [], 1);
cols = (0:nb-1)*L;
first = imin <= imax;
i1 = cols + min(imin, imax); i2 = cols + max(imin, imax);
y1 = ymax; y1(first) = ymin(first); y2 = ymin; y2(first) = ymax(first);
xo = reshape([x(i1(:)) x(i2(:))].', [], 1);
yo = reshape([y1(:) y2(:)].', [], 1);
xo = [xo; x(m+1:end)]; yo = [yo; y(m+1:end)];
X = []; %#ok<NASGU>
end

function [f, A] = ampSpectrum(t, x)
%AMPSPECTRUM  One-sided amplitude, Hann window, coherent-gain corrected:
%   A[k] = 2|X[k]| / sum(w) for interior bins, no doubling at DC / Nyquist.
x = x(isfinite(x)); n = numel(x);
if n < 16, f = []; A = []; return; end
fs = 1/median(diff(t));
x = x - mean(x);
w = 0.5 - 0.5*cos(2*pi*(0:n-1).'/(n-1));
X = fft(x(:).*w);
nh = floor(n/2) + 1;
A = abs(X(1:nh))/sum(w);
if mod(n, 2) == 0, A(2:end-1) = 2*A(2:end-1); else, A(2:end) = 2*A(2:end); end
f = (0:nh-1).'*fs/n;
end
