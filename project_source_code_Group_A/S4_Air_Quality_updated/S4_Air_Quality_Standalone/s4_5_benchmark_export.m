function r = s4_5_benchmark_export(csvPath, co2, outDir, doPlot, postUrl)
% S4-5  Open-data benchmark + Sensor Grid integration for team S4.
%   (a) Ingest an AirKorea-format hourly record for Songdo station #131233
%       (offline mock in the AirKorea OpenAPI JSON layout, written to data/),
%       align KST hour-ending timestamps to our UTC records, and score
%       PM2.5 / PM10: bias, MAE, RMSE, Pearson r, CAI grade agreement.
%   (b) Hourly completeness check (>= 75 % valid minutes, AirKorea rule).
%   (c) Merge all four S4 channels (PM25, PM10, CO2, AQI_CAI_LEVEL) into one
%       Sensor Grid JSON packet, validate it, optionally HTTP POST it.
%   csvPath : S4-4 hourly CSV (S4_4_telemetry.csv)
%   co2     : struct from s4_3_filter (fields t, co2_fir, co2_raw)
if nargin < 3, outDir = pwd; end
if nargin < 4, doPlot = true; end
if nargin < 5, postUrl = ''; end

% ---- read S4-4 hourly output -------------------------------------------------
fid = fopen(csvPath, 'r');
C = textscan(fid, '%s %f %f %f %f %f %f %s %s', 'Delimiter', ',', 'HeaderLines', 1);
fclose(fid);
ts = C{1};  pm25 = C{3};  pm10 = C{4};  cai = C{7};  grade = C{8};  qflag = C{9};
H  = numel(ts);
tUTC = zeros(H,1);
for j = 1:H
    v = sscanf(ts{j}, '%d-%d-%dT%d:%d:%f');
    tUTC(j) = datenum(v(1), v(2), v(3), v(4), v(5), round(v(6)));
end
tKST = tUTC + 9/24;
hourEndKST = ceil(round(tKST*1440)/60)/24;           % xx:59 -> next full hour

% ---- (a) AirKorea-format reference (deterministic offline mock) ------------
st = rng;  rng(131233);
ref25 = round(0.93*pm25 + 1.5 + 2.0*randn(H, 1));
ref10 = round(0.95*pm10 + 2.0 + 3.0*randn(H, 1));
rng(st);
items = cell(H,1);
for j = 1:H
    items{j} = struct('stationName','송도', 'dataTime', datestr(hourEndKST(j), 'yyyy-mm-dd HH:MM'), ...
        'pm25Value', sprintf('%d', ref25(j)), 'pm10Value', sprintf('%d', ref10(j)), ...
        'pm25Flag', [], 'pm10Flag', []);
end
api = struct('response', struct( ...
    'header', struct('resultCode','00', 'resultMsg','NORMAL_CODE (offline mock, synthetic values)'), ...
    'body',   struct('totalCount', H, 'items', {items})));
dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
mockPath = fullfile(dataDir, 'airkorea_131233_mock.json');
writeText(mockPath, jsonencode(api));

% ingest it back the way a real API response would be parsed
A  = jsondecode(readText(mockPath));
it = A.response.body.items;
if isstruct(it), it = num2cell(it); end
refT = zeros(numel(it),1);  r25 = nan(numel(it),1);  r10 = nan(numel(it),1);
for j = 1:numel(it)
    refT(j) = datenum(it{j}.dataTime, 'yyyy-mm-dd HH:MM');
    r25(j)  = str2double(it{j}.pm25Value);
    r10(j)  = str2double(it{j}.pm10Value);
end
[ok, loc] = ismember(round(hourEndKST*24), round(refT*24));
r.n_matched = nnz(ok);
r.pm25 = scores(pm25(ok), r25(loc(ok)));
r.pm10 = scores(pm10(ok), r10(loc(ok)));
gOurs = caiGrade(round(pm25(ok)));  gRef = caiGrade(r25(loc(ok)));
r.grade_agreement = mean(gOurs == gRef);

% ---- (b) completeness -------------------------------------------------------
r.hours_valid = mean(strcmp(qflag, 'GOOD'));
r.completeness_ok = r.hours_valid >= 0.75;

% ---- (c) merged Sensor Grid JSON -------------------------------------------
Ts   = co2.t(2) - co2.t(1);
nPer = round(3600/Ts);
co2h = mean(reshape(co2.co2_fir(1:H*nPer), nPer, H), 1)';
co2r = co2.co2_raw(nPer:nPer:H*nPer);
recs = cell(4*H, 1);
for j = 1:H
    tsj = ts{j};
    recs{4*j-3} = rec(tsj, 'PM25_UG_M3',    C{2}(j), pm25(j), 'ug/m3', qflag{j});
    recs{4*j-2} = rec(tsj, 'PM10_UG_M3',    NaN,     pm10(j), 'ug/m3', 'GOOD');
    recs{4*j-1} = rec(tsj, 'CO2_NDIR_PPM',  round(10*co2r(j))/10, round(10*co2h(j))/10, 'ppm', 'GOOD');
    recs{4*j}   = rec(tsj, 'AQI_CAI_LEVEL', cai(j),  cai(j),  'index', qflag{j});
    recs{4*j}.cai_grade = grade{j};
end
pkt = struct('schema_version','1.0', ...
    'generated_at', datestr(now, 'yyyy-mm-ddTHH:MM:SS'), ...
    'station_id','STATION_TECHNOPARK_AIRQUALITY', 'team','S4', ...
    'latitude',37.3812, 'longitude',126.6620, ...
    'benchmark', struct('source','AirKorea #131233 (offline mock)', ...
        'pm25_rmse', r.pm25.rmse, 'pm10_rmse', r.pm10.rmse, 'grade_agreement', r.grade_agreement), ...
    'records', {recs});
txt = jsonencode(pkt);
jsonPath = fullfile(outDir, 'S4_sensor_grid.json');
writeText(jsonPath, txt);

dec = jsondecode(txt);
need = {'schema_version','generated_at','station_id','latitude','longitude','records'};
r.schema_ok = all(isfield(dec, need)) && numel(dec.records) == 4*H;
r.n_records = 4*H;
r.json_path = jsonPath;

r.post_status = 'skipped';
if ~isempty(postUrl)
    try
        webwrite(postUrl, txt, weboptions('MediaType','application/json', 'Timeout',5));
        r.post_status = 'ok';
    catch e
        r.post_status = ['failed: ' e.message];
    end
end

fprintf('\n--- S4-5 AirKorea benchmark + Sensor Grid export ---\n');
fprintf('Matched hours: %d / %d (completeness %.0f %%, rule >= 75 %%: %s)\n', ...
    r.n_matched, H, 100*r.hours_valid, tf(r.completeness_ok));
fprintf('PM2.5 vs #131233: bias %+.2f | MAE %.2f | RMSE %.2f ug/m3 | r = %.3f\n', r.pm25.bias, r.pm25.mae, r.pm25.rmse, r.pm25.r);
fprintf('PM10  vs #131233: bias %+.2f | MAE %.2f | RMSE %.2f ug/m3 | r = %.3f\n', r.pm10.bias, r.pm10.mae, r.pm10.rmse, r.pm10.r);
fprintf('CAI grade agreement (PM2.5): %.1f %%\n', 100*r.grade_agreement);
fprintf('Sensor Grid JSON: %d records, schema %s, POST %s\n', r.n_records, tf(r.schema_ok), r.post_status);

if doPlot
    fig = figure('Name','S4-5 benchmark','Position',[100 100 1200 420]);
    th = (1:H)';
    subplot(1,3,[1 2]); hold on; grid on;
    plot(th, pm25, 'b', 'LineWidth',1.4); plot(th, r25(loc(ok)), 'ko', 'MarkerSize',4);
    plot(th, pm10, 'Color',[0.55 0.35 0.1], 'LineWidth',1.2); plot(th, r10(loc(ok)), 'ks', 'MarkerSize',4);
    xlabel('Hour'); ylabel('[\mug/m^3]'); xlim([1 H]);
    title('S4-5: S4 hourly PM vs AirKorea #131233 (offline mock)');
    legend('S4 PM_{2.5}','AirKorea PM_{2.5}','S4 PM_{10}','AirKorea PM_{10}','Location','northwest');
    subplot(1,3,3); hold on; grid on;
    plot(r25(loc(ok)), pm25(ok), 'b.', 'MarkerSize',12);
    mx = max([pm25; r25]) + 5;  plot([0 mx], [0 mx], 'k--');
    axis([0 mx 0 mx]); axis square;
    xlabel('AirKorea PM_{2.5}'); ylabel('S4 PM_{2.5}');
    title(sprintf('r = %.3f, RMSE = %.1f', r.pm25.r, r.pm25.rmse));
    print(fig, fullfile(outDir,'S4_5_benchmark.png'), '-dpng', '-r150');
end
end

% ---------------------------------------------------------------------------
function s = scores(x, y)
e = x - y;
s.bias = mean(e);  s.mae = mean(abs(e));  s.rmse = sqrt(mean(e.^2));
c = corrcoef(x, y);  s.r = c(1,2);
end

function g = caiGrade(c)
g = 1 + (c >= 16) + (c >= 36) + (c >= 76);
end

function s = rec(ts, ch, raw, filt, unit, q)
s = struct('timestamp',ts, 'channel',ch, 'raw_value',raw, 'filtered_value',filt, ...
    'unit',unit, 'quality_flag',q);
end

function writeText(p, txt)
fid = fopen(p, 'w', 'n', 'UTF-8');  fprintf(fid, '%s', txt);  fclose(fid);
end

function txt = readText(p)
fid = fopen(p, 'r', 'n', 'UTF-8');  txt = fread(fid, '*char')';  fclose(fid);
end

function s = tf(b)
if b, s = 'OK'; else, s = 'FAIL'; end
end
