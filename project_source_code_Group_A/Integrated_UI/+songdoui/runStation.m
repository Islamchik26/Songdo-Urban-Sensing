function res = runStation(st)
%RUNSTATION  Run one member's original pipeline unchanged and capture it.
%   res = songdoui.runStation(station) executes the member entry point the
%   same way the member runs it by hand (functions are called, scripts are
%   run in an isolated workspace so their CLEAR / CLOSE ALL cannot touch the
%   app), captures the Command Window text and every figure it creates.
%
%   Figures are created invisible and their HandleVisibility is switched
%   off afterwards so a later member script calling CLOSE ALL cannot
%   destroy them. The app shows them embedded and can pop them out.

res = struct('code', st.code, 'ok', false, 'error', '', 'console', '', ...
    'figures', gobjects(0), 'data', [], 'elapsed', 0, 'time', datetime('now'));

for k = 1:numel(st.paths)
    if isfolder(st.paths{k}), addpath(st.paths{k}); end
end

before  = findall(groot, 'Type', 'figure');
oldVis  = get(groot, 'DefaultFigureVisible');
oldDir  = pwd;
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', oldVis));
restoreDir = onCleanup(@() cd(oldDir));
cd(st.folder);

t0 = tic;
try
    switch st.runner
        case 'S1'
            [res.console, res.data] = callCaptured(@run_S1);
        case 'S2'
            [res.console, res.data] = callCaptured(@() run_S2('Plot', true, 'Export', true));
        case 'S3'
            [c1, report] = callCaptured(@run_S3);
            [c2, kma]    = callCaptured(@() run_KMA_observations([], [], [], false));
            [c3, views]  = callCaptured(@() songdoui.s3Views(kma));
            res.console = [c1 newline c2 newline c3];
            res.data = struct('report', report, 'kma', kma, 'views', views);
        case 'script'
            res.console = songdoui.runScriptIsolated(st.script);
        otherwise
            error('songdoui:runner', 'Unknown runner %s', st.runner);
    end
    res.ok = true;
catch err
    res.error = getReport(err, 'extended', 'hyperlinks', 'off');
    res.console = [res.console newline '*** ERROR ***' newline res.error];
end
res.elapsed = toc(t0);

after = findall(groot, 'Type', 'figure');
newFigs = after(~ismember(after, before));
newFigs = newFigs(isvalid(newFigs));
% Keep creation order (findall returns newest first).
newFigs = flipud(newFigs(:));
for k = 1:numel(newFigs)
    newFigs(k).HandleVisibility = 'off';
    try, theme(newFigs(k), 'light'); catch, end   % R2025a+ dark desktop: render member plots as authored %#ok<NOCOMMA>
    newFigs(k).Visible = 'off';
    newFigs(k).CloseRequestFcn = @(f, ~) set(f, 'Visible', 'off'); % pop-out windows only hide
end
res.figures = newFigs;
end

% -------------------------------------------------------------------------
function [txt, out] = callCaptured(fn)
%CALLCAPTURED  evalc for a function handle that returns one value.
out = [];
txt = evalc('out = fn();');
end
