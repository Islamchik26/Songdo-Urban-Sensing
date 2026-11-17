%% ========================================================================
%  Scenario S4-4: Korea MoE CAI (통합대기환경지수) Index Categorization
%  Team S4 — Air Quality & Canyon Dispersion, Techno-Park R&D Strip
%  Station: STATION_TECHNOPARK_AIRQUALITY (37.3812 N, 126.6620 E, 7.8 m)
%
%  Pipeline:
%   synthetic PM2.5/PM10 -> quality flags -> causal 1-h FIR (streamed, zi->zf)
%   -> CAI sub-index (piecewise linear) -> integrated CAI = max(sub-indices)
%   -> grade with Schmitt-style hysteresis -> Sensor Grid JSON + CSV
%
%  Base MATLAB only (R2023b+). Deterministic: rng(42).
%  ========================================================================
clear; clc; close all;
rng(42);

%% 1. Station & sampling parameters
station.id  = "STATION_TECHNOPARK_AIRQUALITY";
station.lat = 37.3812;
station.lon = 126.6620;

Ts    = 60;                          % [s] PM sensor outputs one value per minute
Ndays = 3;
N     = Ndays*24*3600/Ts;            % 4320 samples
t_s   = (0:N-1).' * Ts;
t_h   = t_s / 3600;                  % hours since start
t0    = datetime(2026,10,20,0,0,0,'TimeZone','Asia/Seoul');
tt    = t0 + seconds(t_s);

names_en = ["Good","Moderate","Unhealthy","Very Unhealthy"];
names_ko = ["좋음","보통","나쁨","매우나쁨"];

%% 2. Synthetic street-canyon PM2.5 / PM10 (ground truth + sensor noise)
hod   = mod(t_h, 24);                                  % hour of day (KST)
base  = 18 + 6*sin(2*pi*(hod - 9)/24);                 % diurnal background
rush  = 22*exp(-(hod-8.5).^2/(2*1.0^2)) ...            % morning rush hour
      + 18*exp(-(hod-18.5).^2/(2*1.2^2));              % evening rush hour
haze  = 60*exp(-(t_h-58).^2/(2*5^2));                  % day-3 haze episode
pm25_true = base + rush + haze;

ar25     = filter(1, [1 -0.9], 1.5*randn(N,1));        % correlated optical noise
pm25_raw = max(pm25_true + ar25 + 1.0*randn(N,1), 0);

pm10_true = 1.8*pm25_true + 5;
ar10      = filter(1, [1 -0.9], 2.5*randn(N,1));
pm10_raw  = max(pm10_true + ar10 + 1.5*randn(N,1), 0);

% Inject sensor faults into PM2.5
iDrop  = randperm(N, 15);  pm25_raw(iDrop)  = NaN;                     % dropouts
iSpike = randperm(N, 8);   pm25_raw(iSpike) = pm25_raw(iSpike) + 300;  % soot plume / optical glitch
iNeg   = randperm(N, 2);   pm25_raw(iNeg)   = -5;                      % ADC offset fault

%% 3. Quality flagging (Stage 7) + hold-last-good for filter input
lim.min  = 0;
lim.max  = 1000;                     % [ug/m3] sensor range
lim.dmax = 30/60;                    % [ug/m3 per s] = 30 ug/m3 per minute
[q25, x25] = qc_and_hold(pm25_raw, lim, Ts);
[q10, x10] = qc_and_hold(pm10_raw, lim, Ts);

%% 4. Causal 1-hour moving-average FIR (block streaming, persistent state)
M   = 60;                            % 60 taps = 1 hour at Ts = 60 s
b   = ones(M,1)/M;  a = 1;           % symmetric -> linear phase, delay (M-1)/2 = 29.5 min
zi0 = @(x0) x0*flipud(cumsum(flipud(b(2:end))));   % steady-state IC (no start-up transient)

% (a) batch reference
ma25_batch = filter(b, a, x25, zi0(x25(1)));

% (b) real-time streaming: L-sample blocks, state carried zi -> zf
L    = 30;                           % 30-minute block per timer tick
ma25 = zeros(N,1);
z    = zi0(x25(1));
for k = 1:L:N
    idx = k:min(k+L-1, N);
    [ma25(idx), z] = filter(b, a, x25(idx), z);
end
stream_err = max(abs(ma25 - ma25_batch));

ma10     = filter(b, a, x10, zi0(x10(1)));
ma25_24h = movmean(x25, [1439 0]);   % causal trailing 24-h mean (reference only)

%% 5. CAI sub-indices & integrated CAI
I25_raw     = cai_subindex(pm25_raw, "PM25");          % unfiltered, for comparison
[~, g_1min] = cai_subindex(x25, "PM25");               % 1-min grade, no smoothing
[I25, g25]  = cai_subindex(ma25, "PM25");
I10         = cai_subindex(ma10, "PM10");
CAI         = max(I25, I10);                           % integrated index = worst pollutant
dom         = repmat("PM25", N, 1);  dom(I10 > I25) = "PM10";

%% 6. Grade with asymmetric hysteresis (Schmitt-trigger style)
%  Upgrade immediately when a breakpoint is crossed (public-health safe side);
%  downgrade only after concentration drops 'margin' below the band's lower edge.
g_hys25 = grade_hysteresis(ma25, [0 16 36 76],  3);    % PM2.5 margin 3 ug/m3
g_hys10 = grade_hysteresis(ma10, [0 31 81 151], 5);    % PM10  margin 5 ug/m3
gFinal  = max(g_hys25, g_hys10);

%% 7. Figures
cols  = [0.20 0.45 0.90; 0.20 0.70 0.30; 0.95 0.65 0.10; 0.85 0.15 0.15]; % AirKorea-style
bands = [0 15.5; 15.5 35.5; 35.5 75.5; 75.5 200];

% Fig 1 — PM2.5 raw vs causal filtered on grade bands
f1 = figure('Name','S4-4 PM2.5','Position',[100 100 1100 420]);
hold on;
hP = gobjects(4,1);
for k = 1:4
    hP(k) = patch([0 t_h(end) t_h(end) 0], ...
        [bands(k,1) bands(k,1) bands(k,2) bands(k,2)], cols(k,:), ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none');
end
bad  = q25 ~= "GOOD";
hRaw = plot(t_h, pm25_raw, 'Color', [0.6 0.6 0.6]);
hMA  = plot(t_h, ma25, 'b', 'LineWidth', 1.5);
h24  = plot(t_h, ma25_24h, 'k--', 'LineWidth', 1.2);
hQ   = plot(t_h(bad), x25(bad), 'rx', 'MarkerSize', 8, 'LineWidth', 1.2);
ylim([0 150]); xlim([0 t_h(end)]); grid on;
xlabel('Time [h]'); ylabel('PM_{2.5} [\mug/m^3]');
title('S4-4: PM_{2.5} — raw vs causal 1-h FIR, Korean CAI grade bands');
legend([hP; hRaw; hMA; h24; hQ], ...
    [cellstr(names_en), {'Raw 1-min','Causal 1-h MA','Causal 24-h mean','Flagged (held)'}], ...
    'Location', 'northwest', 'NumColumns', 2);

% Fig 2 — CAI sub-indices and integrated CAI
f2 = figure('Name','S4-4 CAI','Position',[100 100 1100 380]);
plot(t_h, I25, 'b', 'LineWidth', 1.3); hold on;
plot(t_h, I10, 'Color', [0.55 0.35 0.10], 'LineWidth', 1.1);
plot(t_h, CAI, 'k', 'LineWidth', 1.8);
yline([50 100 250], '--', {'Good | Moderate','Moderate | Unhealthy','Unhealthy | Very Unhealthy'});
grid on; xlim([0 t_h(end)]);
xlabel('Time [h]'); ylabel('Index');
title('S4-4: CAI sub-indices and integrated CAI = max(I_{PM2.5}, I_{PM10})');
legend('I_{PM2.5}', 'I_{PM10}', 'CAI', 'Location', 'northwest');

% Fig 3 — grade chatter: no filter vs filter vs filter + hysteresis
f3 = figure('Name','S4-4 Grades','Position',[100 100 1100 620]);
tl = tiledlayout(3,1,'TileSpacing','compact');
G   = {g_1min, g25, g_hys25};
ttl = {'1-min, no filter', '1-h causal MA', '1-h causal MA + hysteresis'};
nTrans = zeros(1,3);
for k = 1:3
    nTrans(k) = nnz(diff(G{k}));
    nexttile;
    stairs(t_h, G{k}, 'LineWidth', 1.2);
    ylim([0.5 4.5]); yticks(1:4); yticklabels(names_en); grid on; xlim([0 t_h(end)]);
    title(sprintf('%s — %d grade transitions', ttl{k}, nTrans(k)));
end
xlabel(tl, 'Time [h]');
title(tl, 'S4-4: PM_{2.5} grade stability');

exportgraphics(f1, 'S4_4_fig1_pm25.png',  'Resolution', 150);
exportgraphics(f2, 'S4_4_fig2_cai.png',   'Resolution', 150);
exportgraphics(f3, 'S4_4_fig3_grades.png','Resolution', 150);

%% 8. Sensor Grid JSON + CSV export (hourly records)
iHr   = (M:M:N).';                                     % end of each hour
tsUTC = tt(iHr);  tsUTC.TimeZone = 'UTC';
tsStr = string(tsUTC, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

recs = cell(2*numel(iHr), 1);
for j = 1:numel(iHr)
    n = iHr(j);
    recs{2*j-1} = struct( ...
        'timestamp',      tsStr(j), ...
        'channel',        "PM25_UG_M3", ...
        'raw_value',      round(pm25_raw(n), 2), ...
        'filtered_value', round(ma25(n), 2), ...
        'unit',           "ug/m3", ...
        'quality_flag',   q25(n));
    recs{2*j} = struct( ...
        'timestamp',          tsStr(j), ...
        'channel',            "AQI_CAI_LEVEL", ...
        'raw_value',          I25_raw(n), ...
        'filtered_value',     CAI(n), ...
        'unit',               "index", ...
        'quality_flag',       q25(n), ...
        'cai_grade',          names_en(gFinal(n)), ...
        'cai_grade_ko',       names_ko(gFinal(n)), ...
        'dominant_pollutant', dom(n));
end

genAt = string(datetime('now','TimeZone','UTC'), "yyyy-MM-dd'T'HH:mm:ss'Z'");
pkt = struct('schema_version', "1.0", 'generated_at', genAt, ...
    'station_id', station.id, 'latitude', station.lat, 'longitude', station.lon, ...
    'records', {recs});

txt = jsonencode(pkt, 'PrettyPrint', true);
fid = fopen('S4_4_telemetry.json', 'w', 'n', 'UTF-8');
fprintf(fid, '%s', txt);
fclose(fid);

T = table(tsStr, round(pm25_raw(iHr),2), round(ma25(iHr),2), round(ma10(iHr),2), ...
    I25(iHr), I10(iHr), CAI(iHr), names_en(gFinal(iHr)).', q25(iHr), ...
    'VariableNames', {'timestamp_utc','pm25_raw','pm25_1h','pm10_1h', ...
                      'cai_pm25','cai_pm10','cai','cai_grade','quality_flag'});
writetable(T, 'S4_4_telemetry.csv');

%% 9. Self-tests (schema, filter, CAI breakpoints, hysteresis)
dec = jsondecode(txt);
assert(all(isfield(dec, {'schema_version','generated_at','station_id','latitude','longitude','records'})), ...
    'JSON: missing top-level field');
assert(numel(dec.records) == 2*numel(iHr), 'JSON: record count');

assert(stream_err < 1e-10, 'Streaming output != batch output');
assert(all(abs(b - flipud(b)) < eps), 'FIR not symmetric (no linear phase)');

[Ichk, gchk] = cai_subindex([0 15 16 35 36 75 76 500 900], "PM25");
assert(isequal(Ichk, [0 50 51 100 101 250 251 500 500]), 'CAI PM2.5 breakpoints');
assert(isequal(gchk, [1 1 2 2 3 3 4 4 4]), 'CAI PM2.5 grades');
[Ichk10, ~] = cai_subindex([30 31 80 81 150 151], "PM10");
assert(isequal(Ichk10, [50 51 100 101 250 251]), 'CAI PM10 breakpoints');

gh = grade_hysteresis([34 36 34 33 32 31 30], [0 16 36 76], 3);
assert(isequal(gh(:).', [2 3 3 3 2 2 2]), 'Hysteresis latching');

%% 10. Summary
fprintf('\n===== S4-4 CAI Categorization — %s =====\n', station.id);
fprintf('Samples: %d (Ts = %d s, %d days)\n', N, Ts, Ndays);
fprintf('Quality flags PM2.5: GOOD %d | DROPOUT %d | OUT_OF_RANGE %d | SUSPECT_JUMP %d\n', ...
    sum(q25=="GOOD"), sum(q25=="DROPOUT"), sum(q25=="OUT_OF_RANGE"), sum(q25=="SUSPECT_JUMP"));
fprintf('Streaming vs batch max error: %.2e\n', stream_err);
fprintf('FIR group delay: %.1f samples = %.1f min\n', (M-1)/2, (M-1)/2*Ts/60);
fprintf('Grade transitions — raw: %d | 1-h MA: %d | 1-h MA + hysteresis: %d\n', nTrans);
fprintf('Peak CAI: %d (%s) at t = %.1f h\n', max(CAI), names_en(gFinal(find(CAI==max(CAI),1))), ...
    t_h(find(CAI==max(CAI),1)));
for k = 1:4
    fprintf('  Time in %-15s: %5.1f %%\n', names_en(k), 100*mean(gFinal==k));
end
fprintf('All self-tests passed. Exported S4_4_telemetry.json / .csv and 3 figures.\n');

%% ========================= Local functions ==============================
function [q, xh] = qc_and_hold(x, lim, Ts)
% Quality flags (DROPOUT / OUT_OF_RANGE / SUSPECT_JUMP / GOOD) and
% zero-order hold of the last GOOD value so the causal filter never sees faults.
N = numel(x);  q = repmat("GOOD", N, 1);  xh = x;
last = NaN;
for n = 1:N
    if isnan(x(n))
        q(n) = "DROPOUT";
    elseif x(n) < lim.min || x(n) > lim.max
        q(n) = "OUT_OF_RANGE";
    elseif ~isnan(last) && abs(x(n) - last)/Ts > lim.dmax
        q(n) = "SUSPECT_JUMP";
    else
        last = x(n);
    end
end
good  = (q == "GOOD");
first = find(good, 1);
for n = 1:N
    if ~good(n)
        if n == 1, xh(n) = x(first); else, xh(n) = xh(n-1); end
    end
end
end

function [I, g] = cai_subindex(C, pollutant)
% Korean CAI sub-index: I = (I_hi-I_lo)/(BP_hi-BP_lo)*(C-BP_lo) + I_lo
% Concentration rounded to integer ug/m3 as in AirKorea reporting.
switch pollutant
    case "PM25", BP = [0 15; 16 35; 36 75; 76 500];
    case "PM10", BP = [0 30; 31 80; 81 150; 151 600];
    otherwise,   error('Unknown pollutant: %s', pollutant);
end
IX = [0 50; 51 100; 101 250; 251 500];
Cr = min(max(round(C), 0), BP(end,2));
Cr(isnan(C)) = NaN;                       % max() would turn NaN into 0
I = nan(size(C));  g = zeros(size(C));
for k = 1:4
    m = Cr >= BP(k,1) & Cr <= BP(k,2);
    I(m) = (IX(k,2)-IX(k,1))/(BP(k,2)-BP(k,1)) * (Cr(m)-BP(k,1)) + IX(k,1);
    g(m) = k;
end
I = round(I);
end

function g = grade_hysteresis(C, lowBP, margin)
% Asymmetric Schmitt trigger over 4 grades:
%   up   : Cr >= lowBP(s+1)            (immediate)
%   down : Cr <  lowBP(s) - margin     (delayed)
Cr = round(C);  N = numel(C);  g = zeros(N,1);
s = find(Cr(1) >= lowBP, 1, 'last');
for n = 1:N
    while s < numel(lowBP) && Cr(n) >= lowBP(s+1), s = s + 1; end
    while s > 1 && Cr(n) < lowBP(s) - margin,      s = s - 1; end
    g(n) = s;
end
end
