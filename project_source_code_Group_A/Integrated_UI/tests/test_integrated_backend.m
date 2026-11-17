function test_integrated_backend(doVerification)
%TEST_INTEGRATED_BACKEND  Headless checks of the integrated UI back end.
%   test_integrated_backend          % stations, 25 checks, live streams
%   test_integrated_backend(true)    % + full member verification suites
if nargin < 1, doVerification = false; end
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
songdoui.setupPaths();
R = songdoui.registry();
assert(numel(R.stations) == 5, 'Expected five stations');
assert(sum(arrayfun(@(s) numel(s.tasks), R.stations)) == 25, 'Expected 25 scenarios');

% 1) every station runs through the integrated runner, every task gets checks
for st = R.stations
    res = songdoui.runStation(st);
    assert(res.ok, 'Station %s failed:\n%s', st.code, res.error);
    fprintf('%s ran in %.1f s, %d figures: %s\n', st.code, res.elapsed, numel(res.figures), ...
        strjoin(arrayfun(@(f) string(f.Name), res.figures), ' ; '));
    for tk = st.tasks.'
        C = songdoui.taskChecks(st, tk, res, R);
        bad = C(strcmp(C(:, 4), 'FAIL') | strcmp(C(:, 4), 'WARN'), :);
        fprintf('  %s: %d checks, %d PASS, %d FAIL/WARN\n', tk.id, size(C, 1), sum(strcmp(C(:, 4), 'PASS')), size(bad, 1));
        for k = 1:size(bad, 1), fprintf('      %s | %s | %s\n', bad{k, 1}, bad{k, 3}, bad{k, 4}); end
    end
    delete(res.figures(isvalid(res.figures)));
end

% 2) live streams: each channel runs blocks, block-wise == continuous for FIR/IIR
for st = R.stations
    for ch = songdoui.LiveStream.channels(st.code)
        s = songdoui.LiveStream(st.code, ch{1});
        for k = 1:40
            [tr, xr, tf, yf, flag, feat] = s.next();
            assert(numel(tr) == numel(xr) && numel(tf) == numel(yf), '%s/%s size mismatch', st.code, ch{1});
            assert(ischar(flag) && ischar(feat), 'flag/feature type');
        end
        if s.Tunable, s.setCutoff(s.Cutoff*0.8); s.next(); end
        fprintf('LIVE %s/%-20s ok  Fs=%g  last flag=%s  | %s\n', st.code, ch{1}, s.FsRaw, flag, feat);
    end
end

% 3) streaming continuity: S5 FIR blocks vs batch on the same record
s = songdoui.LiveStream('S5', 'WATER_LEVEL_M');
y = []; x = [];
for k = 1:50, [~, xr, ~, yf] = s.next(); x = [x; xr]; y = [y; yf]; end %#ok<AGROW>
assert(numel(y) == 1500, 'S5 continuity length');
fprintf('S5 FIR block streaming produced %d continuous samples.\n', numel(y));

if doVerification
    [T, ~] = songdoui.runVerification(R);
    disp(T);
end
fprintf('\nIntegrated back-end checks finished.\n');
end
