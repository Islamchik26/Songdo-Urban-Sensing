function [T, log] = runVerification(R, progressFcn)
%RUNVERIFICATION  Run every member's own test suite + cross-station checks.
%   [T, log] = songdoui.runVerification() returns a table with columns
%   Station | Suite | Result | Detail, and the captured console text.
%
%   S1  tests/test_S1.m                (member script)
%   S2  tests/test_S2.m                (member function, 38 checks)
%   S3  tests/run_all_tests.m          (member function, 5 groups)
%   S4  tests/test_S4.m (31 checks) + S4-4 embedded asserts + run_S4 R.Checks
%   S5  no member test file: output-based checks on run_S5 figures/JSON
%   ALL Sensor Grid JSON schema for all five stations + station registry

if nargin < 1 || isempty(R), R = songdoui.registry(); end
if nargin < 2, progressFcn = @(varargin) []; end
rows = cell(0, 4);
log = '';
S = R.stations;
byCode = @(c) S(strcmp({S.code}, c));

% ---- S1 ---------------------------------------------------------------
progressFcn(0.05, 'S1: tests/test_S1.m');
st = byCode('S1');
[ok, txt] = captured(st, @() songdoui.runScriptIsolated(fullfile(st.folder, 'tests', 'test_S1.m')));
nP = numel(regexp(txt, '\<PASS\>'));
rows(end+1, :) = {'S1', 'tests/test_S1.m (member)', pf(ok), sprintf('%d PASS lines', nP)};
log = [log banner('S1 test_S1') txt];

% ---- S2 ---------------------------------------------------------------
progressFcn(0.2, 'S2: tests/test_S2.m');
st = byCode('S2');
addpath(fullfile(st.folder, 'tests'));
okS2 = false;
[ok, txt] = captured(st, @() runS2());
tok = regexp(txt, '(\d+) / (\d+) passed', 'tokens', 'once');
detail = '';
if ~isempty(tok), detail = sprintf('%s / %s passed', tok{1}, tok{2}); okS2 = strcmp(tok{1}, tok{2}); end
rows(end+1, :) = {'S2', 'tests/test_S2.m (member)', pf(ok && okS2), detail};
log = [log banner('S2 test_S2') txt];

% ---- S3 ---------------------------------------------------------------
progressFcn(0.35, 'S3: tests/run_all_tests.m (about 30 s)');
st = byCode('S3');
[ok, txt] = captured(st, @() run_all_tests());
tok = regexp(txt, 'All (\d+) MATLAB test groups passed', 'tokens', 'once');
detail = 'see log'; if ~isempty(tok), detail = sprintf('%s / %s test groups passed', tok{1}, tok{1}); end
rows(end+1, :) = {'S3', 'tests/run_all_tests.m (member)', pf(ok), detail};
log = [log banner('S3 run_all_tests') txt];

% ---- S4 ---------------------------------------------------------------
progressFcn(0.6, 'S4: tests/test_S4.m + run_S4');
st = byCode('S4');
[ok, txt] = captured(st, @() songdoui.runScriptIsolated(fullfile(st.folder, 'tests', 'test_S4.m')));
tok = regexp(txt, '(\d+) passed, (\d+) failed', 'tokens', 'once');
detail = 'see log';
if ~isempty(tok), detail = sprintf('%s passed, %s failed', tok{1}, tok{2}); ok = ok && strcmp(tok{2}, '0'); end
rows(end+1, :) = {'S4', 'tests/test_S4.m (member, S4-1/2/3/5)', pf(ok), detail};
log = [log banner('S4 test_S4') txt];
res = songdoui.runStation(st);
okS4 = res.ok && contains(res.console, 'All self-tests passed');
rows(end+1, :) = {'S4', 'S4-4 embedded self-tests (member asserts)', pf(okS4), ...
    'schema, FIR symmetry, streaming==batch, CAI breakpoints, hysteresis'};
tok = regexp(res.console, '(\d+) / (\d+) checks passed', 'tokens', 'once');
okRun = res.ok && ~isempty(tok) && strcmp(tok{1}, tok{2});
detail = 'see log'; if ~isempty(tok), detail = sprintf('%s / %s checks passed', tok{1}, tok{2}); end
rows(end+1, :) = {'S4', 'run_S4 R.Checks (member, S4-1..S4-5)', pf(okRun), detail};
log = [log banner('S4 run_S4') res.console];
delete(res.figures(isvalid(res.figures)));

% ---- S5 ---------------------------------------------------------------
progressFcn(0.72, 'S5: output-based checks on run_S5');
st = byCode('S5');
res = songdoui.runStation(st);
log = [log banner('S5 run_S5') res.console];
for tk = st.tasks(1:4).'
    C = songdoui.taskChecks(st, tk, res, R);
    for k = 2:size(C, 1)          % row 1 is "pipeline executed"
        rows(end+1, :) = {'S5', sprintf('%s %s (integrated check)', tk.id, C{k, 1}), C{k, 4}, C{k, 3}}; %#ok<AGROW>
    end
end
delete(res.figures(isvalid(res.figures)));

% ---- Cross-station ----------------------------------------------------
progressFcn(0.9, 'Cross-station Sensor Grid conformance');
for st = S
    if isfile(st.jsonFile)
        v = songdoui.validateSensorGrid(st.jsonFile, R);
        res = pf(v.ok); if v.ok && ~isempty(v.warnings), res = 'WARN'; end
        rows(end+1, :) = {st.code, 'Sensor Grid JSON schema (Section 5.3)', res, v.summary}; %#ok<AGROW>
    else
        rows(end+1, :) = {st.code, 'Sensor Grid JSON schema (Section 5.3)', 'FAIL', ...
            'export not found - run the station first'}; %#ok<AGROW>
    end
end
ids = {S.stationId};
D = songdoui.haversineKm([S.lat], [S.lon]);
maxD = max(D(:));
rows(end+1, :) = {'ALL', 'Station registry: 5 unique stations', pf(numel(unique(ids)) == 5), strjoin(ids, ', ')};
rows(end+1, :) = {'ALL', 'Haversine: all stations within Songdo (< 6 km apart)', pf(maxD < 6), ...
    sprintf('max pairwise distance %.2f km', maxD)};
dKnown = songdoui.haversineKm([0 0], [0 1]);
rows(end+1, :) = {'ALL', 'Haversine accuracy: 1 deg of longitude at equator', pf(abs(dKnown(1, 2) - 111.195) < 0.01), ...
    sprintf('%.3f km (expected 111.195 km)', dKnown(1, 2))};

progressFcn(1, 'Done');
T = cell2table(rows, 'VariableNames', {'Station', 'Suite', 'Result', 'Detail'});
end

% -------------------------------------------------------------------------
function [ok, txt] = captured(st, fn)
for k = 1:numel(st.paths), if isfolder(st.paths{k}), addpath(st.paths{k}); end, end
before = findall(groot, 'Type', 'figure');
oldVis = get(groot, 'DefaultFigureVisible'); oldDir = pwd;
set(groot, 'DefaultFigureVisible', 'off');
c1 = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis));
c2 = onCleanup(@() cd(oldDir));
cd(st.folder);
ok = true; out = [];
try
    txt = evalc('out = fn();');
    if ischar(out) || isstring(out), txt = [txt char(out)]; end   % nested evalc returns text
catch err
    ok = false;
    txt = getReport(err, 'extended', 'hyperlinks', 'off');
end
after = findall(groot, 'Type', 'figure');
delete(after(~ismember(after, before)));
end

function out = runS2()
out = test_S2();          % returns true/false instead of erroring
if ~out, error('songdoui:S2', 'test_S2 reported failures'); end
end

function s = pf(tf)
if tf, s = 'PASS'; else, s = 'FAIL'; end
end

function s = banner(name)
s = sprintf('\n==================== %s ====================\n', name);
end
