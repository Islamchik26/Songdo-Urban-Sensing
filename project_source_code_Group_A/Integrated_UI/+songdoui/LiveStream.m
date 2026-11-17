classdef LiveStream < handle
%LIVESTREAM  Common causal block-streaming runtime for all five stations.
%
%   s = songdoui.LiveStream('S2', 'MIC_VOLTS_48K');
%   [tRaw, xRaw, tFilt, yFilt, flag, feature] = s.next();   % one timer tick
%
%   Every channel is processed block-by-block with persistent state
%   (filter zi -> zf, median buffers, Schmitt latches, decimator phase), so
%   concatenated block outputs equal batch processing. No filtfilt.
%
%   Where a member exposes a callable streaming engine it is used directly:
%     S2 -> songdo.acoustic.AcousticChain   (S2 member code)
%     S3 -> songdo.core.processBlock        (S3 member code)
%   S1 / S4 / S5 were delivered as scripts, so their signal models and
%   filters are reproduced here with the member's parameters (S1 Butterworth
%   40 Hz + 12-bit ADC + 0.75/0.20 V hysteresis, S4 60-tap MA + CAI grades,
%   S5 61-tap Hann windowed-sinc + 7-point median + 2.1 %/C salinity).

    properties (SetAccess = private)
        Code
        Channel
        Unit         = ''
        FsRaw        = 1
        FsFilt       = 1
        BlockRaw     = 10
        WindowSec    = 10
        Cutoff       = NaN
        Tunable      = false
        CutoffLabel  = 'Cutoff fc (Hz)'
        Stages       = repmat({''}, 1, 7)
        Source       = ''
        TimeUnit     = 's'
        TimeScale    = 1
        Blocks       = 0
        SamplesIn    = 0
    end

    properties (Access = private)
        Raw          % raw record (column) that playback loops over
        Aux = struct()
        Pos = 0
        b
        a
        zi
        Chain
        DecOut = 0
        Cfg
        State
        LastRaw = NaN
        Limits = [-Inf Inf]
        MaxRate = Inf
        Feat = struct()
    end

    methods (Static)
        function list = channels(code)
            switch code
                case 'S1', list = {'PED_PRESSURE_MAT_V', 'PED_FOOTSTEP_DV'};
                case 'S2', list = {'MIC_VOLTS_48K', 'SPL_A_WEIGHTED_PA'};
                case 'S3', list = {'AIR_TEMP_C', 'REL_HUMIDITY_PCT', 'WIND_SPEED_MPS'};
                case 'S4', list = {'PM25_UG_M3', 'AQI_CAI_LEVEL'};
                case 'S5', list = {'WATER_LEVEL_M', 'TURBIDITY_NTU', 'SALINITY_PSU'};
                otherwise, list = {};
            end
        end
    end

    methods
        function obj = LiveStream(code, channel)
            obj.Code = code;
            obj.Channel = channel;
            switch code
                case 'S1', obj.initS1();
                case 'S2', obj.initS2();
                case 'S3', obj.initS3();
                case 'S4', obj.initS4();
                case 'S5', obj.initS5();
                otherwise, error('songdoui:LiveStream', 'Unknown station %s', code);
            end
            obj.reset();
        end

        function reset(obj)
            obj.Pos = 0; obj.Blocks = 0; obj.SamplesIn = 0; obj.DecOut = 0;
            obj.LastRaw = NaN;
            switch obj.Code
                case 'S1'
                    obj.zi = filterSteadyState(obj.b, obj.a, obj.Raw(1));
                    obj.Feat = struct('armed', true, 'pos', 0, 'neg', 0, 'state', 0, 'in', 0, 'out', 0);
                case 'S2'
                    obj.Chain.reset();
                    obj.Feat = struct('pA', zeros(0, 1), 'xd', zeros(0, 1), 'siren', 0, 'eta', 0);
                case 'S3'
                    obj.State = songdo.core.initState(obj.Cfg);
                case 'S4'
                    obj.zi = []; obj.Feat = struct('last25', NaN, 'last10', NaN, 'hold25', NaN, 'hold10', NaN, ...
                        'zi10', [], 'g25', 0, 'g10', 0);
                case 'S5'
                    obj.zi = zeros(numel(obj.b) - 1, 1);
                    obj.Feat = struct('buf', nan(7, 1), 'init', false);
            end
        end

        function setCutoff(obj, fc)
            %SETCUTOFF  Live re-tuning at the next block boundary, state kept.
            if ~obj.Tunable, return; end
            nyq = obj.FsRaw/2;
            if ~(isfinite(fc) && fc > 0 && fc < nyq)
                error('songdoui:cutoff', 'Cutoff must be between 0 and Nyquist (%.4g %s).', nyq, 'Hz');
            end
            obj.Cutoff = fc;
            switch obj.Code
                case 'S1'   % same order -> same state length, zi retained
                    [obj.b, obj.a] = butter2(fc, obj.FsRaw);
                case 'S3'
                    obj.Cfg.tempLowpassHz = fc;   % member core retunes poles, keeps state
                case 'S5'   % same FIR length -> zi retained
                    obj.b = hannSinc(61, fc, obj.FsRaw);
            end
            obj.updateStages();
        end

        function [tRaw, xRaw, tFilt, yFilt, flag, feature] = next(obj)
            L = obj.BlockRaw;
            n = numel(obj.Raw);
            idx = mod(obj.Pos + (0:L-1), n) + 1;
            obj.Pos = mod(obj.Pos + L, n);
            tRaw = (obj.SamplesIn + (0:L-1)).' / obj.FsRaw;
            xRaw = obj.Raw(idx);
            switch obj.Code
                case 'S1', [tFilt, yFilt, flag, feature] = obj.stepS1(idx, xRaw, tRaw);
                case 'S2', [tFilt, yFilt, xRaw, flag, feature] = obj.stepS2(xRaw);
                case 'S3', [tFilt, yFilt, xRaw, flag, feature] = obj.stepS3(idx, tRaw);
                case 'S4', [tFilt, yFilt, xRaw, flag, feature] = obj.stepS4(idx, tRaw);
                case 'S5', [tFilt, yFilt, xRaw, flag, feature] = obj.stepS5(idx, tRaw);
            end
            if numel(xRaw) ~= numel(tRaw), tRaw = tFilt; end   % S2 SPL: "raw" is the flat 8 kHz pressure
            obj.SamplesIn = obj.SamplesIn + L;
            obj.Blocks = obj.Blocks + 1;
        end
    end

    % =====================================================================
    methods (Access = private)
        % ------------------------------------------------------------ S1
        function initS1(obj)
            rs = RandStream('twister', 'Seed', 42);
            obj.FsRaw = 200; obj.FsFilt = 200; obj.BlockRaw = 10;       % 50 ms blocks
            t = (0:60*obj.FsRaw-1).' / obj.FsRaw;
            obj.Source = 'S1 member signal model (run_S1.m) regenerated, 60 s loop';
            switch obj.Channel
                case 'PED_PRESSURE_MAT_V'
                    x = 1.65 + 0.35*sin(2*pi*2*t) + 0.22*sin(2*pi*65*t) + 0.015*randn(rs, size(t));
                    for et = [3 5 7 9 12 15 18 27 43 58]
                        k = round(et*obj.FsRaw) + (0:5);
                        x(k) = x(k) + 0.9*exp(-(0:5).'/2);
                    end
                    obj.Raw = min(max(x, 0), 3.3);
                    obj.Unit = 'V'; obj.WindowSec = 3; obj.Tunable = true; obj.Cutoff = 40;
                    [obj.b, obj.a] = butter2(obj.Cutoff, obj.FsRaw);
                    obj.Limits = [0 3.3];
                case 'PED_FOOTSTEP_DV'
                    x = zeros(size(t)); tt = 0.5;
                    while tt < 59
                        k = round(tt*obj.FsRaw) + (1:20);
                        if rand(rs) < 0.7, x(k) = 1; else, x(k) = -1; end
                        if rand(rs) < 0.15                          % short contact chatter
                            kc = k(end) + 40 + (1:5); x(kc(kc <= numel(x))) = 1;
                        end
                        tt = tt + 0.35 + 0.9*rand(rs);
                    end
                    obj.Raw = x + 0.04*randn(rs, size(t));
                    obj.Unit = 'V'; obj.WindowSec = 8;
                    obj.b = 1; obj.a = 1;
                    obj.Limits = [-3.3 3.3];
            end
            obj.updateStages();
        end

        function [tF, y, flag, feat] = stepS1(obj, ~, x, tR)
            tF = tR;
            switch obj.Channel
                case 'PED_PRESSURE_MAT_V'
                    [yf, obj.zi] = filter(obj.b, obj.a, x, obj.zi);
                    q = 3.3/4096;
                    y = min(max(round(yf/q), 0), 4095)*q;              % 12-bit mid-tread ADC
                    e = y - yf;
                    feat = sprintf('ADC q = %.3f mV | block error var / (q^2/12) = %.2f | SQNR_th = 74.0 dB', ...
                        1e3*q, var(e, 1)/(q^2/12));
                case 'PED_FOOTSTEP_DV'
                    y = zeros(size(x)); F = obj.Feat;
                    for k = 1:numel(x)                                 % S1 member hysteresis rule
                        if ~F.armed
                            if abs(x(k)) <= 0.20, F.armed = true; F.pos = 0; F.neg = 0; F.state = 0; end
                        elseif x(k) >= 0.75
                            F.pos = F.pos + 1; F.neg = 0;
                            if F.pos >= 15, F.in = F.in + 1; F.armed = false; F.state = 1; end
                        elseif x(k) <= -0.75
                            F.neg = F.neg + 1; F.pos = 0;
                            if F.neg >= 15, F.out = F.out + 1; F.armed = false; F.state = -1; end
                        else
                            F.pos = 0; F.neg = 0;
                        end
                        y(k) = F.state;
                    end
                    obj.Feat = F;
                    net = F.in - F.out;
                    feat = sprintf('Entries %d | Exits %d | Net %d | density %.4f people/m^2 (A = 250 m^2)', ...
                        F.in, F.out, net, net/250);
            end
            flag = obj.genericFlag(x);
        end

        % ------------------------------------------------------------ S2
        function initS2(obj)
            fx = songdo.acoustic.make_s2_fixture();
            obj.Aux.sens = fx.Sensitivity;
            obj.Chain = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity);
            obj.FsRaw = fx.Fs; obj.FsFilt = obj.Chain.FsOut;
            obj.BlockRaw = round(0.05*obj.FsRaw);                     % 2400 samples = 50 ms
            obj.Raw = fx.volts;
            obj.Source = 'S2 member fixture make_s2_fixture() + AcousticChain (member code), 24 s loop';
            switch obj.Channel
                case 'MIC_VOLTS_48K'
                    obj.Unit = 'V'; obj.WindowSec = 0.1; obj.Limits = [-1 1];
                case 'SPL_A_WEIGHTED_PA'
                    obj.Unit = 'Pa'; obj.WindowSec = 0.5; obj.FsRaw = fx.Fs; obj.Limits = [-50 50];
            end
            obj.updateStages();
        end

        function [tF, y, xOut, flag, feat] = stepS2(obj, x)
            [pA, xd] = obj.Chain.process(x);
            tF = (obj.DecOut + (0:numel(xd)-1)).' / obj.FsFilt;
            obj.DecOut = obj.DecOut + numel(xd);
            F = obj.Feat;
            F.pA = [F.pA; pA]; F.pA = F.pA(max(1, end-obj.FsFilt+1):end);       % last 1 s
            F.xd = [F.xd; xd]; F.xd = F.xd(max(1, end-511):end);               % last STFT frame
            leq = 10*log10(mean(F.pA.^2)/(20e-6)^2);
            if numel(F.xd) == 512
                S = songdo.acoustic.stft_features(F.xd, obj.FsFilt);
                F.eta = S.SirenRatio(end);
                [~, F.siren] = songdo.acoustic.schmitt_trigger(F.eta, 0.55, 0.35, F.siren);
            end
            obj.Feat = F;
            sirenTxt = 'off'; if F.siren, sirenTxt = 'ON'; end
            feat = sprintf('L_Aeq,1s = %.1f dBA | siren eta = %.2f | EVENT_SIREN_FLAG = %s', leq, F.eta, sirenTxt);
            switch obj.Channel
                case 'MIC_VOLTS_48K'
                    xOut = x; y = xd;
                case 'SPL_A_WEIGHTED_PA'
                    xOut = xd / obj.Aux.sens; y = pA;
            end
            flag = obj.genericFlag(xOut);
        end

        % ------------------------------------------------------------ S3
        function initS3(obj)
            obj.Cfg = songdo.core.defaultConfig();
            in = songdo.io.generateScenario(obj.Cfg, 'mixed', obj.Cfg.durationSeconds);
            obj.Aux.input = in;
            obj.FsRaw = obj.Cfg.fsHz; obj.FsFilt = obj.FsRaw; obj.BlockRaw = 5;
            obj.WindowSec = 60;
            obj.Raw = (1:height(in)).';                                % row indices
            obj.Source = 'S3 member generateScenario(''mixed'') + songdo.core.processBlock (member code), 180 s loop';
            switch obj.Channel
                case 'AIR_TEMP_C',       obj.Unit = 'C';   obj.Tunable = true; obj.Cutoff = obj.Cfg.tempLowpassHz;
                case 'REL_HUMIDITY_PCT', obj.Unit = '%';
                case 'WIND_SPEED_MPS',   obj.Unit = 'm/s';
            end
            obj.updateStages();
        end

        function [tF, y, x, flag, feat] = stepS3(obj, idx, tR)
            blk = obj.Aux.input(obj.Raw(idx), :);
            blk.time_s = tR;                                           % continuous clock across loops
            [out, obj.State] = songdo.core.processBlock(blk, obj.State, obj.Cfg);
            tF = tR;
            switch obj.Channel
                case 'AIR_TEMP_C'
                    x = blk.AIR_TEMP_C; y = out.AIR_TEMP_FILTERED_C; q = out.TEMP_QUALITY;
                    feat = sprintf('Truth %.2f C | PT100 %.2f C | compensated %.2f C | pole fc = %.3g Hz', ...
                        blk.TRUE_AIR_TEMP_C(end), x(end), y(end), obj.Cfg.tempLowpassHz);
                case 'REL_HUMIDITY_PCT'
                    x = blk.REL_HUMIDITY_PCT; y = out.REL_HUMIDITY_FILTERED_PCT; q = out.HUMIDITY_QUALITY;
                    feat = sprintf('5-pt causal median + 2 %%/s rate check | latest flag %s', q(end));
                case 'WIND_SPEED_MPS'
                    x = out.WIND_SPEED_MPS; y = out.WIND_MEAN_SPEED_MPS; q = out.WIND_QUALITY;
                    feat = sprintf('10 s vector mean %.2f m/s | direction %.0f deg | 3 s gust %.2f m/s', ...
                        y(end), out.WIND_MEAN_DIR_DEG(end), out.WIND_GUST_MPS(end));
            end
            flag = worstFlag(cellstr(q));
        end

        % ------------------------------------------------------------ S4
        function initS4(obj)
            rs = RandStream('twister', 'Seed', 42);
            Ts = 60; N = 3*24*3600/Ts;
            th = (0:N-1).' * Ts / 3600; hod = mod(th, 24);
            base = 18 + 6*sin(2*pi*(hod - 9)/24);
            rush = 22*exp(-(hod-8.5).^2/2) + 18*exp(-(hod-18.5).^2/(2*1.2^2));
            haze = 60*exp(-(th-58).^2/(2*5^2));
            p25 = base + rush + haze;
            r25 = max(p25 + filter(1, [1 -0.9], 1.5*randn(rs, N, 1)) + randn(rs, N, 1), 0);
            r10 = max(1.8*p25 + 5 + filter(1, [1 -0.9], 2.5*randn(rs, N, 1)) + 1.5*randn(rs, N, 1), 0);
            r25(randperm(rs, N, 15)) = NaN;
            k = randperm(rs, N, 8); r25(k) = r25(k) + 300;
            r25(randperm(rs, N, 2)) = -5;
            obj.Aux.pm10 = r10;
            obj.Raw = r25;
            obj.FsRaw = 1/Ts; obj.FsFilt = obj.FsRaw; obj.BlockRaw = 10;      % 10 minutes per tick
            obj.WindowSec = 24*3600; obj.TimeUnit = 'h'; obj.TimeScale = 1/3600;
            obj.b = ones(60, 1)/60; obj.a = 1;
            obj.Limits = [0 1000]; obj.MaxRate = 30/60;
            obj.Source = 'S4 member signal model (S4_4_cai_categorization.m) regenerated, 3-day loop';
            switch obj.Channel
                case 'PM25_UG_M3',    obj.Unit = 'ug/m3';
                case 'AQI_CAI_LEVEL', obj.Unit = 'index';
            end
            obj.updateStages();
        end

        function [tF, y, xOut, flag, feat] = stepS4(obj, idx, tR)
            F = obj.Feat; x25 = obj.Raw(idx); x10 = obj.Aux.pm10(idx);
            q = cell(numel(idx), 1); h25 = zeros(size(x25)); h10 = zeros(size(x10));
            for k = 1:numel(idx)                                       % S4 member QC + hold-last-good
                [q{k}, F.last25, F.hold25] = qcHold(x25(k), F.last25, F.hold25, obj.Limits, obj.MaxRate, 60);
                [~,    F.last10, F.hold10] = qcHold(x10(k), F.last10, F.hold10, obj.Limits, obj.MaxRate, 60);
                h25(k) = F.hold25; h10(k) = F.hold10;
            end
            if isempty(obj.zi)
                obj.zi = filterSteadyState(obj.b, obj.a, h25(1));
                F.zi10 = filterSteadyState(obj.b, obj.a, h10(1));
            end
            [m25, obj.zi] = filter(obj.b, obj.a, h25, obj.zi);
            [m10, F.zi10] = filter(obj.b, obj.a, h10, F.zi10);
            I25 = caiSub(m25, 'PM25'); I10 = caiSub(m10, 'PM10');
            for k = 1:numel(idx)
                F.g25 = gradeHys(m25(k), [0 16 36 76], 3, F.g25);
                F.g10 = gradeHys(m10(k), [0 31 81 151], 5, F.g10);
            end
            obj.Feat = F;
            names = {'Good', 'Moderate', 'Unhealthy', 'Very Unhealthy'};
            g = max(F.g25, F.g10);
            feat = sprintf('PM2.5 1-h %.1f | PM10 1-h %.1f ug/m3 | CAI %d -> grade %s', m25(end), m10(end), max(I25(end), I10(end)), names{g});
            tF = tR;
            switch obj.Channel
                case 'PM25_UG_M3',    xOut = x25; y = m25;
                case 'AQI_CAI_LEVEL', xOut = caiSub(x25, 'PM25'); y = max(I25, I10);
            end
            flag = worstFlag(q);
        end

        % ------------------------------------------------------------ S5
        function initS5(obj)
            rs = RandStream('twister', 'Seed', 42);
            t = (0:24*3600-1).'; N = numel(t);
            T2 = 12.42*3600;
            lvl = 1.8 + 0.9*sin(2*pi*t/T2) + 0.15*sin(2*pi*t/(T2/2));
            sl = t >= 14*3600 & t <= 15.5*3600;
            lvl(sl) = lvl(sl) - 0.45*sin(pi*(t(sl) - 14*3600)/(1.5*3600));
            waves = 0.22*sin(2*pi*0.42*t) + 0.18*sin(2*pi*0.65*t + 0.4);
            temp = 15.2 + 2.5*sin(2*pi*(t - 6*3600)/86400) + 0.08*randn(rs, N, 1);
            sal = 28.5 - 1.2*sin(2*pi*t/T2);
            cond = sal.*(1 + 0.021*(temp - 15)) + 0.15*randn(rs, N, 1);
            turb = 4.2 + 0.8*sin(2*pi*t/86400) + 28*exp(-((t - 8*3600)/1800).^2) ...
                 + 35*exp(-((t - 17*3600)/2400).^2) + 0.6*randn(rs, N, 1);
            obj.Aux.temp = temp;
            obj.FsRaw = 1; obj.FsFilt = 1; obj.BlockRaw = 30;          % 30 s per tick
            obj.WindowSec = 2*3600; obj.TimeUnit = 'h'; obj.TimeScale = 1/3600;
            obj.Source = 'S5 member signal model (run_S5.m) regenerated, 24 h loop';
            obj.b = 1; obj.a = 1;
            switch obj.Channel
                case 'WATER_LEVEL_M'
                    obj.Raw = lvl + waves + 0.05*randn(rs, N, 1);
                    obj.Unit = 'm'; obj.Tunable = true; obj.Cutoff = 0.05;
                    obj.b = hannSinc(61, obj.Cutoff, obj.FsRaw);
                    obj.Limits = [-1 5];
                case 'TURBIDITY_NTU'
                    obj.Raw = max(0, turb); obj.Unit = 'NTU'; obj.Limits = [0 15];
                case 'SALINITY_PSU'
                    obj.Raw = cond; obj.Unit = 'PSU'; obj.Limits = [26 32];
            end
            obj.updateStages();
        end

        function [tF, y, x, flag, feat] = stepS5(obj, idx, tR)
            x = obj.Raw(idx); tF = tR;
            switch obj.Channel
                case 'WATER_LEVEL_M'
                    if obj.SamplesIn == 0, obj.zi = filterSteadyState(obj.b, obj.a, x(1)); end
                    [y, obj.zi] = filter(obj.b, obj.a, x, obj.zi);
                    feat = sprintf('Hann windowed-sinc FIR N = 61, fc = %.3g Hz, group delay 30 s | level %.3f m', obj.Cutoff, y(end));
                case 'TURBIDITY_NTU'
                    F = obj.Feat; y = zeros(size(x));
                    for k = 1:numel(x)                                 % trailing 7-sample median
                        F.buf = [F.buf(2:end); x(k)];
                        y(k) = median(F.buf, 'omitnan');
                    end
                    obj.Feat = F;
                    st = 'below'; if y(end) > 15, st = 'ABOVE'; end
                    feat = sprintf('7-pt causal median %.2f NTU (%s MEIS 15 NTU limit)', y(end), st);
                case 'SALINITY_PSU'
                    y = x ./ (1 + 0.021*(obj.Aux.temp(idx) - 15));
                    feat = sprintf('Compensated %.2f PSU at %.2f C (MEIS band 26-32)', y(end), obj.Aux.temp(idx(end)));
            end
            flag = obj.genericFlag(y);
        end

        % ------------------------------------------------------- helpers
        function flag = genericFlag(obj, x)
            %GENERICFLAG  Handbook eq. (15) on the block: worst flag wins.
            flag = 'GOOD';
            if any(~isfinite(x)), flag = 'DROPOUT'; return; end
            if any(x < obj.Limits(1) | x > obj.Limits(2)), flag = 'OUT_OF_RANGE'; return; end
            d = abs(diff([obj.LastRaw; x(:)])) * obj.FsRaw;
            if any(d > obj.MaxRate), flag = 'SUSPECT_JUMP'; end
            obj.LastRaw = x(end);
        end

        function updateStages(obj)
            fc = obj.Cutoff;
            switch obj.Code
                case 'S1'
                    obj.Stages = {'Crowd footsteps / presence', 'Piezo mat, PIR tau=0.8 s', ...
                        sprintf('Butterworth LP fc=%g Hz', fc), '200 Hz, 12-bit, 3.3 V', ...
                        'Causal IIR (DF-II-T, zi)', 'Schmitt 0.75/0.20 V, density', 'PED_PIR_COUNT JSON'};
                    if strcmp(obj.Channel, 'PED_FOOTSTEP_DV'), obj.Stages{3} = 'Differential pickup'; end
                case 'S2'
                    obj.Stages = {'Traffic sound p(t)', 'Mic 20 mV/Pa', '60 Hz notch Q=30', ...
                        '48 kHz, 24-bit', 'FIR 101 taps, /6, A-wt IIR', 'Leq 1 s, STFT, siren eta', 'SPL/LEQ/SIREN JSON'};
                case 'S3'
                    obj.Stages = {'Air temp / RH / wind', 'PT100 tau=12 s', 'Analog LP 2 Hz', ...
                        '10 Hz, 16-bit', sprintf('Lag comp + 3 poles %.3g Hz', obj.Cfg.tempLowpassHz), ...
                        'Median, vector mean, gust', '1-min Sensor Grid'};
                case 'S4'
                    obj.Stages = {'PM2.5 / PM10', 'Laser scattering', '(not modelled)', ...
                        '1 sample/min', 'QC + 60-tap MA (zi)', 'CAI + grade hysteresis', 'PM25 / CAI JSON'};
                case 'S5'
                    obj.Stages = {'Tide, waves, runoff', 'Pressure / NTU / C-T cell', '(not modelled)', ...
                        '1 Hz', 'FIR N=61 / median', 'M2, thresholds', 'Waterfront JSON'};
                    if strcmp(obj.Channel, 'WATER_LEVEL_M'), obj.Stages{5} = sprintf('Hann FIR N=61 fc=%.3g', fc); end
            end
        end
    end
end

% =========================================================================
function [b, a] = butter2(fc, Fs)
% S1 member formula: 2nd-order Butterworth via pre-warped bilinear transform.
k = tan(pi*fc/Fs); den = 1 + sqrt(2)*k + k^2;
b = [k^2 2*k^2 k^2]/den;
a = [1 2*(k^2-1)/den (1 - sqrt(2)*k + k^2)/den];
end

function b = hannSinc(N, fc, Fs)
% S5 member formula: Hann windowed-sinc lowpass, unity DC gain.
n = (0:N-1).'; M = (N-1)/2; fn = fc/Fs;
h = 2*fn*ones(N, 1);
nz = n ~= M;
h(nz) = sin(2*pi*fn*(n(nz) - M)) ./ (pi*(n(nz) - M));
b = h .* (0.5 - 0.5*cos(2*pi*n/(N-1)));
b = b / sum(b);
end

function zi = filterSteadyState(b, a, x0)
% DF-II-T state that makes the filter start at steady state for input x0.
b = b(:); a = a(:);
n = max(numel(a), numel(b)); b(end+1:n) = 0; a(end+1:n) = 0;
if n == 1, zi = zeros(0, 1); return; end
y0 = x0 * sum(b) / sum(a);
zi = zeros(n-1, 1);
for k = n-1:-1:1
    nextZ = 0; if k < n-1, nextZ = zi(k+1); end
    zi(k) = b(k+1)*x0 - a(k+1)*y0 + nextZ;
end
end

function f = worstFlag(q)
order = {'DROPOUT', 'OUT_OF_RANGE', 'SUSPECT_JUMP', 'GOOD'};
f = 'GOOD';
for k = 1:numel(order)
    if any(strcmp(q, order{k})), f = order{k}; return; end
end
end

function [q, last, held] = qcHold(x, last, held, lim, dmax, Ts)
% S4 member qc_and_hold rule, one sample at a time.
if isnan(x)
    q = 'DROPOUT';
elseif x < lim(1) || x > lim(2)
    q = 'OUT_OF_RANGE';
elseif ~isnan(last) && abs(x - last)/Ts > dmax
    q = 'SUSPECT_JUMP';
else
    q = 'GOOD'; last = x;
end
if strcmp(q, 'GOOD'), held = x; elseif isnan(held), held = 0; end
end

function I = caiSub(C, pollutant)
% S4 member Korean CAI sub-index (piecewise linear, integer concentration).
switch pollutant
    case 'PM25', BP = [0 15; 16 35; 36 75; 76 500];
    case 'PM10', BP = [0 30; 31 80; 81 150; 151 600];
end
IX = [0 50; 51 100; 101 250; 251 500];
Cr = min(max(round(C), 0), BP(end, 2));
I = nan(size(C));
for k = 1:4
    m = Cr >= BP(k, 1) & Cr <= BP(k, 2);
    I(m) = (IX(k, 2) - IX(k, 1))/(BP(k, 2) - BP(k, 1)) * (Cr(m) - BP(k, 1)) + IX(k, 1);
end
I(isnan(C)) = NaN;
I = round(I);
end

function s = gradeHys(C, lowBP, margin, s)
% S4 member asymmetric grade hysteresis, one sample at a time.
Cr = round(C);
if s == 0, s = find(Cr >= lowBP, 1, 'last'); if isempty(s), s = 1; end, end
while s < numel(lowBP) && Cr >= lowBP(s+1), s = s + 1; end
while s > 1 && Cr < lowBP(s) - margin,      s = s - 1; end
end
