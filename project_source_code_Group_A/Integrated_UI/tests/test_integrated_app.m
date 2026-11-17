function test_integrated_app(fullRun)
%TEST_INTEGRATED_APP  Drive the integrated UI programmatically.
%   test_integrated_app        % run S2 + S5, every node, every live channel
%   test_integrated_app(true)  % also unified run of all 5 + verification
if nargin < 1, fullRun = false; end
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
app = SongdoIntegratedApp();
cleanup = onCleanup(@() delete(app));
R = app.Registry;

% every node is selectable before anything runs
for st = R.stations
    app.selectNode(st.code);
    for tk = st.tasks.', app.selectNode(tk.id); end
end
fprintf('All 30 tree nodes selectable before running.\n');

codes = {'S5', 'S2'};
if fullRun, codes = {R.stations.code}; end
for c = codes
    app.selectNode([c{1} '-1']);
    app.runSelected(false);
    st = R.stations(strcmp({R.stations.code}, c{1}));
    for tk = st.tasks.'
        app.selectNode(tk.id);                 % renders the first view (exportgraphics)
    end
    fprintf('%s run + all 5 scenario views rendered.\n', c{1});
end
if fullRun
    app.runAllStations();
    T = app.runVerificationSuites();
    disp(T);
end

% live instrument: every station / channel, retune, export
for st = R.stations
    for ch = songdoui.LiveStream.channels(st.code)
        app.liveSelect(st.code, ch{1});
        app.liveStep(12);
    end
end
app.liveSelect('S5', 'WATER_LEVEL_M');
app.liveStep(5);
app.liveRetune(0.03);
app.liveStep(5);
f = app.liveExport();
v = songdoui.validateSensorGrid(f, R);
assert(v.ok, 'Live export invalid: %s', v.summary);
fprintf('Live export %s -> %s\n', f, v.summary);
T = app.validateAllExports();
disp(T(:, 1:4));
fprintf('\nIntegrated app test finished OK.\n');
end
