function R = run_S4(varargin)
% RUN_S4  Team S4 — Air Quality & Canyon Dispersion, all five scenarios.
%   R = run_S4;                       % all scenarios, figures, exports to output/
%   R = run_S4('Plot', false);        % headless
%   R = run_S4('Post', true);         % also POST the Sensor Grid JSON to the mock receiver
%
%   S4-1  sensor transduction (first-order PM2.5 / NDIR CO2, exact ZOH)
%   S4-2  ADC sampling, aliasing, mid-tread quantization
%   S4-3  causal windowed-sinc FIR + IIR DF-II for CO2, block streaming
%   S4-4  Korean CAI categorization with hysteresis   (S4_4_cai_categorization.m)
%   S4-5  AirKorea #131233 benchmark + merged Sensor Grid JSON export
p = inputParser;
addParameter(p, 'Plot', true);
addParameter(p, 'Post', false);
addParameter(p, 'Url',  'http://localhost:8080/api/v1/telemetry');
parse(p, varargin{:});
o = p.Results;

root   = fileparts(mfilename('fullpath'));
outDir = fullfile(root, 'output');
if ~exist(outDir, 'dir'), mkdir(outDir); end
if ~o.Plot, set(0, 'DefaultFigureVisible', 'off'); end
cleanup = onCleanup(@() set(0, 'DefaultFigureVisible', 'on'));

fprintf('===== Team S4 — STATION_TECHNOPARK_AIRQUALITY (37.3812 N, 126.6620 E) =====\n');
R.s1 = s4_1_sensor(true, outDir);
R.s2 = s4_2_adc(true, outDir);
R.s3 = s4_3_filter(true, outDir);

% S4-4 is a standalone script (it calls clear/close all), so run it in its
% own function workspace with output/ as the current folder.
here = pwd;
t44 = now;
cd(outDir);
try
    runScript44(root);
catch e
    cd(here);  rethrow(e);
end
cd(here);
csv44 = fullfile(outDir, 'S4_4_telemetry.csv');
d44 = dir(csv44);
fresh44 = ~isempty(d44) && d44.datenum >= t44 - 1/86400;   % written by this run, not a stale copy

url = '';  if o.Post, url = o.Url; end
R.s5 = s4_5_benchmark_export(csv44, R.s3, outDir, true, url);

checks = {
    'S4-1 ZOH exact (PM2.5)',          R.s1.pm25.zoh_err < 1e-9
    'S4-1 t63 = tau (CO2)',            abs(R.s1.co2.t63 - R.s1.co2.tau) < 0.05
    'S4-1 tau identified within 5 %',  abs(R.s1.co2.tau_hat/R.s1.co2.tau - 1) < 0.05
    'S4-2 SQNR within 0.5 dB of rule', R.s2.sqnr_maxdev < 0.5
    'S4-2 alias frequency',            abs(R.s2.f_alias_meas - R.s2.f_alias_theory) < 1e-3
    'S4-3 FIR stopband >= 50 dB',      R.s3.stop_atten_dB >= 50
    'S4-3 group delay (M-1)/2',        abs(R.s3.group_delay_samples - (R.s3.M-1)/2) < 0.01
    'S4-3 streaming == batch',         max(R.s3.stream_err_fir, R.s3.stream_err_iir) < 1e-9
    'S4-4 exports written to output/', fresh44
    'S4-5 JSON schema',                R.s5.schema_ok
    'S4-5 completeness >= 75 %',       R.s5.completeness_ok };
R.Checks = cell2table(checks, 'VariableNames', {'Check','Pass'});
fprintf('\n'); disp(R.Checks);
fprintf('%d / %d checks passed. Outputs in %s\n', nnz([checks{:,2}]), size(checks,1), outDir);
end

function runScript44(root)
% Isolated workspace: the script's own clear/close all cannot touch run_S4.
% The script is called by name (not RUN(fullpath), which switches to the
% script's folder), so its JSON/CSV/PNG land in the current folder, output/.
addpath(root);
S4_4_cai_categorization;
end
