function v = s3Views(kma)
%S3VIEWS  Per-scenario S3 figures built on the S3 member's own API.
%   run_S3 exports one PNG and closes its figure, so the integrated UI
%   re-creates one figure per scenario by calling the member's
%   songdo.io.generateScenario + songdo.core.processBlock exactly the way
%   run_S3 does (fixed-size causal blocks, state carried between blocks).

cfg   = songdo.core.defaultConfig();
mixed = songdo.io.generateScenario(cfg, 'mixed', cfg.durationSeconds);
out   = streamBlocks(mixed, cfg);
clean = songdo.io.generateScenario(cfg, 'temperature_plunge', 180);
cOut  = streamBlocks(clean, cfg);

rawDelay  = crossing(clean.time_s, clean.AIR_TEMP_C, 22.5, 30) - 30;
compDelay = crossing(cOut.time_s, cOut.AIR_TEMP_FILTERED_C, 22.5, 30) - 30;
v.rawDelay = rawDelay;
v.compDelay = compDelay;
v.reduction = 100*(1 - compDelay/rawDelay);
v.humidityFlags = countFlags(out.HUMIDITY_QUALITY);
v.pressureFactor = mean(out.SEA_LEVEL_PRESSURE_HPA ./ mixed.PRESSURE_HPA, 'omitnan');
v.maxGust = max(out.WIND_GUST_MPS);
fprintf('S3-1 (integrated view): t50 delay %.2f s -> %.2f s, reduction %.1f %%\n', ...
    rawDelay, compDelay, v.reduction);

% S3-1 -------------------------------------------------------------------
f = figure('Name', 'S3-1 | Thermal lag compensation', 'Color', 'w', 'Position', [80 80 1200 700]);
ax = axes(f);
plot(ax, clean.time_s, clean.TRUE_AIR_TEMP_C, 'k--', 'LineWidth', 1.4); hold(ax, 'on');
plot(ax, clean.time_s, clean.AIR_TEMP_C, 'Color', [0.85 0.45 0.1], 'LineWidth', 1.6);
plot(ax, cOut.time_s, cOut.AIR_TEMP_FILTERED_C, 'Color', [0.1 0.45 0.85], 'LineWidth', 1.8);
yline(ax, 22.5, ':', '50 % crossing');
xlim(ax, [20 90]); grid(ax, 'on');
xlabel(ax, 'Time (s)'); ylabel(ax, 'Temperature (\circC)');
legend(ax, {'True air temperature', 'PT100 output (\tau = 12 s)', 'Compensated + 3 causal poles'}, 'Location', 'northeast');
title(ax, sprintf('S3-1  Clean 5 \\circC plunge: t_{50} delay %.2f s \\rightarrow %.2f s  (%.1f %% reduction, target \\geq 65 %%)', ...
    rawDelay, compDelay, v.reduction));

% S3-2 -------------------------------------------------------------------
f = figure('Name', 'S3-2 | Wind vector averaging', 'Color', 'w', 'Position', [80 80 1200 700]);
tl = tiledlayout(f, 2, 1, 'TileSpacing', 'compact');
ax = nexttile(tl);
plot(ax, mixed.time_s, [mixed.WIND_U_MPS, mixed.WIND_V_MPS]); grid(ax, 'on');
ylabel(ax, 'm/s'); legend(ax, {'u (east-west)', 'v (north-south)'}, 'Location', 'best');
title(ax, 'S3-2  Raw orthogonal components at 10 Hz');
ax = nexttile(tl);
plot(ax, out.time_s, [out.WIND_SPEED_MPS, out.WIND_MEAN_SPEED_MPS, out.WIND_GUST_MPS], 'LineWidth', 1.2);
grid(ax, 'on'); xlabel(ax, 'Time (s)'); ylabel(ax, 'm/s');
yyaxis(ax, 'right'); plot(ax, out.time_s, out.WIND_MEAN_DIR_DEG, ':'); ylabel(ax, 'Direction (deg)');
legend(ax, {'Instant scalar', '10 s vector mean', '3 s peak gust', 'Vector-mean direction'}, 'Location', 'best');
title(ax, sprintf('Vector-averaged speed / direction and 3 s gust (max gust %.2f m/s)', v.maxGust));

% S3-3 -------------------------------------------------------------------
f = figure('Name', 'S3-3 | Humidity median + QC', 'Color', 'w', 'Position', [80 80 1200 700]);
ax = axes(f);
plot(ax, mixed.time_s, mixed.REL_HUMIDITY_PCT, 'Color', [0.7 0.7 0.7]); hold(ax, 'on');
plot(ax, out.time_s, out.REL_HUMIDITY_FILTERED_PCT, 'b', 'LineWidth', 1.6);
bad = out.HUMIDITY_QUALITY ~= "GOOD";
plot(ax, out.time_s(bad), mixed.REL_HUMIDITY_PCT(bad), 'rx', 'MarkerSize', 7);
grid(ax, 'on'); xlabel(ax, 'Time (s)'); ylabel(ax, 'RH (%)');
legend(ax, {'Raw (salt-mist dropouts)', '5-point causal median + rate check', 'Flagged samples'}, 'Location', 'best');
title(ax, sprintf('S3-3  Humidity cleaning: %s', flagText(v.humidityFlags)));

% S3-4 -------------------------------------------------------------------
f = figure('Name', 'S3-4 | Sea-level pressure', 'Color', 'w', 'Position', [80 80 1200 700]);
ax = axes(f);
plot(ax, mixed.time_s, mixed.PRESSURE_HPA, 'LineWidth', 1.3); hold(ax, 'on');
plot(ax, out.time_s, out.SEA_LEVEL_PRESSURE_HPA, 'LineWidth', 1.6);
grid(ax, 'on'); xlabel(ax, 'Time (s)'); ylabel(ax, 'Pressure (hPa)');
legend(ax, {'Station pressure (h = 6.2 m)', 'Reduced to mean sea level'}, 'Location', 'best');
title(ax, sprintf('S3-4  Hypsometric reduction, factor P_0/P_{sta} = %.6f', v.pressureFactor));

% S3-5 : member's real KMA observation plot (exported by run_KMA_observations)
png = '';
if nargin > 0 && isstruct(kma) && isfield(kma, 'output_files') && isfield(kma.output_files, 'plot')
    png = kma.output_files.plot;
end
if ~isempty(png) && isfile(png)
    f = figure('Name', 'S3 | KMA observations (station 512)', 'Color', 'w', 'Position', [80 80 1000 900]);
    ax = axes(f, 'Position', [0 0 1 1]);
    image(ax, imread(png)); axis(ax, 'image', 'off');
end
end

% -------------------------------------------------------------------------
function out = streamBlocks(input, cfg)
state = songdo.core.initState(cfg);
parts = cell(ceil(height(input)/cfg.blockSamples), 1); p = 0;
for first = 1:cfg.blockSamples:height(input)
    p = p + 1; last = min(first + cfg.blockSamples - 1, height(input));
    [parts{p}, state] = songdo.core.processBlock(input(first:last, :), state, cfg);
end
out = vertcat(parts{:});
end

function t = crossing(time, value, target, start)
i = find(time >= start & value <= target, 1);
if isempty(i), t = NaN; return; end
if i == 1 || value(i) == value(i-1), t = time(i); return; end
t = time(i-1) + (target - value(i-1))*(time(i) - time(i-1))/(value(i) - value(i-1));
end

function c = countFlags(q)
names = {'GOOD', 'DROPOUT', 'OUT_OF_RANGE', 'SUSPECT_JUMP'};
c = struct();
for k = 1:numel(names), c.(names{k}) = sum(q == names{k}); end
end

function s = flagText(c)
s = sprintf('GOOD %d | DROPOUT %d | OUT\\_OF\\_RANGE %d | SUSPECT\\_JUMP %d', ...
    c.GOOD, c.DROPOUT, c.OUT_OF_RANGE, c.SUSPECT_JUMP);
end
