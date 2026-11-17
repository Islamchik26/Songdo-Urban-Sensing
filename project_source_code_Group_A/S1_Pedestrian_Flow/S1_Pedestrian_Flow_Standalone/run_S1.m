function result = run_S1()
% RUN_S1 Team S1 Pedestrian Flow demonstration with readable engineering plots.
% Run from this folder in MATLAB R2023b or later. Signals are synthetic.
clc; close all; rng(42,'twister');

projectDir = fileparts(mfilename('fullpath'));
outDir = fullfile(projectDir,'output');
if ~exist(outDir,'dir'), mkdir(outDir); end

Fs = 200;
durationSec = 600;                 % 10-minute overview for crowd dynamics
t = (0:1/Fs:durationSec-1/Fs)';
N = numel(t);

% S1-1: normalized person-presence step at t=1 s.
personStep = double(t >= 1);

% S1-2: pressure-mat signal: 2 Hz physical motion, 65 Hz interference,
% low noise, and short footstep-like impacts. Long-term plots focus on S1-3/4;
% this diagnostic intentionally uses a seconds-scale zoom to reveal filtering.
pressureRaw = 1.65 + 0.35*sin(2*pi*2*t) ...
    + 0.22*sin(2*pi*65*t) + 0.015*randn(N,1);
for eventTime = [3 5 7 9 12 15 18 27 43 58 87 104 137 168 212 257 301 344 389 437 481 526 573]
    idx = round(eventTime*Fs)+(0:5);
    idx = idx(idx>=1 & idx<=N);
    if ~isempty(idx)
        pressureRaw(idx) = pressureRaw(idx) + 0.9*exp(-(0:numel(idx)-1)'/2);
    end
end
pressureRaw = min(max(pressureRaw,0),3.3);

% S1-3: bursty, deterministic crowd-flow schedule over ten minutes.
% Different arrival/exit rates produce rises, plateaus, drawdowns, and recovery.
pulseSamples = 20;                 % 100 ms; detector requires 15 samples
entryTimes = [ ...
    makeEventTimes(5,70,.52), ...
    makeEventTimes(75,135,.32), ...
    makeEventTimes(140,190,.42), ...
    makeEventTimes(200,240,.30), ...
    makeEventTimes(275,330,.35), ...
    makeEventTimes(380,425,.40), ...
    makeEventTimes(465,515,.31), ...
    makeEventTimes(530,548,.50)];
exitTimes = [ ...
    makeEventTimes(192,199,.80), ...
    makeEventTimes(242,270,.55), ...
    makeEventTimes(332,377,.58), ...
    makeEventTimes(428,460,.55), ...
    makeEventTimes(518,529,.40), ...
    makeEventTimes(550,599,.20)];

deltaV = zeros(N,1);
deltaV = paintPulses(deltaV,entryTimes,pulseSamples,Fs,+1.0);
deltaV = paintPulses(deltaV,exitTimes,pulseSamples,Fs,-1.0);
% A few sub-duration pulses illustrate rejection of contact chatter.
for eventTime = [72.2 270.5 462.0]
    idx = round(eventTime*Fs)+(1:5);
    idx = idx(idx>=1 & idx<=N);
    deltaV(idx) = 1.0;
end

result = s1_process(t,personStep,pressureRaw,deltaV,Fs);
s1_export(result,fullfile(outDir,'S1_telemetry.json'), ...
    fullfile(outDir,'S1_telemetry.csv'));
save(fullfile(outDir,'S1_results.mat'),'result');

% Polished dark engineering palette.
figPosition = [60 50 1440 900];
bg = [0.035 0.047 0.071];
panel = [0.055 0.071 0.105];
fg = [0.88 0.92 0.98];
muted = [0.48 0.56 0.68];
cyan = [0.13 0.82 0.98];
orange = [1.00 0.54 0.20];
green = [0.18 0.91 0.65];
magenta = [0.98 0.30 0.63];
yellow = [1.00 0.78 0.20];
blue = [0.35 0.62 0.98];

% -------------------------------------------------------------------------
% Figure 1 — PIR response. A local 0–6 s axis is essential: tau = 0.8 s,
% so a 600 s axis compresses the response into an invisible vertical edge.
% -------------------------------------------------------------------------
stepView = t <= 6;
f1 = figure('Name','S1-1 | PIR Sensor Response','Color',bg, ...
    'NumberTitle','off','Position',figPosition);
ax1 = axes('Parent',f1,'Color',panel); hold(ax1,'on');
plot(ax1,t(stepView),personStep(stepView),'--','Color',cyan,'LineWidth',2.2);
plot(ax1,t(stepView),result.pirOutput(stepView)/2.5,'Color',orange,'LineWidth',2.6);
xline(ax1,1,':','Step input','Color',muted,'LineWidth',1.2, ...
    'LabelVerticalAlignment','middle','LabelHorizontalAlignment','left');
yline(ax1,.1,':','10%','Color',muted,'LineWidth',1.0);
yline(ax1,.9,':','90%','Color',muted,'LineWidth',1.0);
xline(ax1,1+.8*log(10),'-.' ,'t_{90}','Color',green,'LineWidth',1.15);
xline(ax1,1+4*.8,':','2% settling','Color',yellow,'LineWidth',1.15, ...
    'LabelVerticalAlignment','bottom','LabelHorizontalAlignment','left');
set(ax1,'XLim',[0 6],'YLim',[-.04 1.08]);
grid(ax1,'on'); box(ax1,'on');
xlabel(ax1,'TIME (s)','Color',fg); ylabel(ax1,'NORMALIZED RESPONSE','Color',fg);
title(ax1,'S1-1  /  FIRST-ORDER PIR SENSOR RESPONSE (0–6 s)','Color',fg,'FontSize',16,'FontWeight','bold');
legend(ax1,{'Input step','Sensor output / gain'},'Location','southeast', ...
    'TextColor',fg,'Color',panel,'EdgeColor',muted);
styleDarkAxes(ax1,fg,muted);
text(ax1,.98,.10,sprintf('GAIN  %.1f   |   TIME CONSTANT  %.1f s   |   10–90%% RISE  %.2f s', ...
    2.5,.8,.8*log(9)),'Units','normalized','HorizontalAlignment','right', ...
    'Color',cyan,'FontSize',10,'FontWeight','bold','BackgroundColor',panel,'Margin',6);
saveas(f1,fullfile(outDir,'S1_1_PIR_Response.png'));

% -------------------------------------------------------------------------
% Figure 2 — filter comparison on a meaningful seconds-scale window, plus
% a separate sub-second ADC-error zoom. Do not plot 120,000 error samples
% across 600 s: the overlapping line segments become a solid coloured block.
% -------------------------------------------------------------------------
f2 = figure('Name','S1-2 | Filtering and ADC','Color',bg, ...
    'NumberTitle','off','Position',figPosition);
tl2 = tiledlayout(f2,2,1,'TileSpacing','compact','Padding','compact');
ax2a = nexttile(tl2,1); set(ax2a,'Color',panel); hold(ax2a,'on');
filterView = t <= 3;
plot(ax2a,t(filterView),pressureRaw(filterView),'Color',muted,'LineWidth',.75);
plot(ax2a,t(filterView),result.pressureFiltered(filterView),'Color',cyan,'LineWidth',1.7);
% Use occasional markers for quantized samples so that its tiny ADC step does
% not completely hide the filtered curve at the full-voltage scale.
markIdx = find(filterView);
markIdx = markIdx(1:5:end);
plot(ax2a,t(markIdx),result.pressureQuantized(markIdx),'o','Color',orange, ...
    'MarkerSize',2.7,'MarkerFaceColor',orange,'LineStyle','none');
set(ax2a,'XLim',[0 3]);
grid(ax2a,'on'); box(ax2a,'on');
ylabel(ax2a,'VOLTAGE (V)','Color',fg);
title(ax2a,'S1-2  /  LOW-PASS FILTERING AND 12-BIT ADC (0–3 s DETAIL)', ...
    'Color',fg,'FontSize',15,'FontWeight','bold');
legend(ax2a,{'Raw input','Filtered output','Quantized samples (every 25 ms)'}, ...
    'Location','northeast','TextColor',fg,'Color',panel,'EdgeColor',muted);
styleDarkAxes(ax2a,fg,muted);

ax2b = nexttile(tl2,2); set(ax2b,'Color',panel); hold(ax2b,'on');
errorView = t <= .25;
errIdx = find(errorView);
stem(ax2b,t(errIdx),1e3*result.quantizationError(errIdx), ...
    'Color',magenta,'Marker','none','LineWidth',.85);
yline(ax2b,1e3*result.metrics.adc_step_v/2,'--','+0.5 LSB', ...
    'Color',yellow,'LineWidth',1.1,'LabelHorizontalAlignment','right');
yline(ax2b,-1e3*result.metrics.adc_step_v/2,'--','-0.5 LSB', ...
    'Color',yellow,'LineWidth',1.1,'LabelHorizontalAlignment','right');
set(ax2b,'XLim',[0 .25],'YLim',[-.48 .48]);
grid(ax2b,'on'); box(ax2b,'on');
xlabel(ax2b,'TIME (s) — 250 ms ADC DETAIL','Color',fg);
ylabel(ax2b,'QUANTIZATION ERROR (mV)','Color',magenta);
title(ax2b,'ADC ERROR MAGNIFIED — HALF-LSB BOUNDS','Color',fg,'FontSize',12,'FontWeight','bold');
styleDarkAxes(ax2b,fg,muted);
saveas(f2,fullfile(outDir,'S1_2_Filter_ADC.png'));

% -------------------------------------------------------------------------
% Figure 3 — full 10-minute event-count history, plus a readable raw pulse
% window. Full-run totals are shown only on the full-run panel.
% -------------------------------------------------------------------------
f3 = figure('Name','S1-3 | Pedestrian Event Detection','Color',bg, ...
    'NumberTitle','off','Position',figPosition);
tl3 = tiledlayout(f3,2,1,'TileSpacing','compact','Padding','compact');
ax3a = nexttile(tl3,1); set(ax3a,'Color',panel); hold(ax3a,'on');
overviewIdx = 1:20:N;             % 10 Hz overview, still captures event-count changes
stairs(ax3a,t(overviewIdx),result.entryCount(overviewIdx),'Color',green,'LineWidth',1.9);
stairs(ax3a,t(overviewIdx),result.exitCount(overviewIdx),'--','Color',magenta,'LineWidth',1.9);
ylabel(ax3a,'CUMULATIVE EVENTS','Color',fg);
title(ax3a,'S1-3  /  HYSTERESIS EVENT COUNTS — FULL 10-MINUTE RUN', ...
    'Color',fg,'FontSize',15,'FontWeight','bold');
grid(ax3a,'on'); box(ax3a,'on'); set(ax3a,'XLim',[0 durationSec]);
legend(ax3a,{'Detected entries','Detected exits'},'Location','northwest', ...
    'TextColor',fg,'Color',panel,'EdgeColor',muted);
styleDarkAxes(ax3a,fg,muted);
text(ax3a,.985,.12,sprintf('TOTALS  %d ENTRIES  /  %d EXITS', ...
    result.metrics.total_entries,result.metrics.total_exits), ...
    'Units','normalized','HorizontalAlignment','right','Color',green, ...
    'FontSize',10,'FontWeight','bold','BackgroundColor',panel,'Margin',6);

ax3b = nexttile(tl3,2); set(ax3b,'Color',panel); hold(ax3b,'on');
pulseView = t <= 8;
plot(ax3b,t(pulseView),deltaV(pulseView),'Color',cyan,'LineWidth',1.25);
yline(ax3b,.75,'--','ENTRY THRESHOLD +0.75 V','Color',green,'LineWidth',1.1, ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','bottom');
yline(ax3b,-.75,'--','EXIT THRESHOLD -0.75 V','Color',magenta,'LineWidth',1.1, ...
    'LabelHorizontalAlignment','left','LabelVerticalAlignment','top');
entryMarkerIdx = find(result.entryEvent & pulseView);
exitMarkerIdx = find(result.exitEvent & pulseView);
if ~isempty(entryMarkerIdx), plot(ax3b,t(entryMarkerIdx),.92*ones(size(entryMarkerIdx)), ...
    'v','Color',green,'MarkerFaceColor',green,'MarkerSize',5,'LineStyle','none'); end
if ~isempty(exitMarkerIdx), plot(ax3b,t(exitMarkerIdx),-.92*ones(size(exitMarkerIdx)), ...
    '^','Color',magenta,'MarkerFaceColor',magenta,'MarkerSize',5,'LineStyle','none'); end
set(ax3b,'XLim',[0 8],'YLim',[-1.08 1.08]);
grid(ax3b,'on'); box(ax3b,'on');
xlabel(ax3b,'TIME (s)','Color',fg); ylabel(ax3b,'DIFFERENTIAL VOLTAGE (V)','Color',cyan);
title(ax3b,'PULSE DETAIL — FIRST 8 s (MARKERS SHOW ACCEPTED EVENTS)', ...
    'Color',fg,'FontSize',12,'FontWeight','bold');
styleDarkAxes(ax3b,fg,muted);
saveas(f3,fullfile(outDir,'S1_3_Event_Detection.png'));

% -------------------------------------------------------------------------
% Figure 4 — long-form crowd dynamics: density, rate, and resulting alarm.
% Rate uses a causal 2 s smoother in s1_process.m to prevent numerical
% derivative spikes at every quantized count step from looking like a filled area.
% -------------------------------------------------------------------------
f4 = figure('Name','S1-4 | Density and Surge Alarm','Color',bg, ...
    'NumberTitle','off','Position',figPosition);
tl4 = tiledlayout(f4,3,1,'TileSpacing','compact','Padding','compact');
plotIdx = 1:20:N;                  % 10 Hz is ample for this 600 s overview
ax4a = nexttile(tl4,1); set(ax4a,'Color',panel); hold(ax4a,'on');
plot(ax4a,t(plotIdx),result.density(plotIdx),'Color',muted,'LineWidth',.7);
plot(ax4a,t(plotIdx),result.densitySmoothed(plotIdx),'Color',cyan,'LineWidth',2.0);
yline(ax4a,2.5,'--','Density threshold 2.5 people/m^2','Color',yellow, ...
    'LineWidth',1.25,'LabelHorizontalAlignment','left');
ylabel(ax4a,'DENSITY (people/m^2)','Color',cyan);
title(ax4a,'S1-4  /  ESTIMATED PEDESTRIAN DENSITY — FULL 10-MINUTE RUN', ...
    'Color',fg,'FontSize',15,'FontWeight','bold');
legend(ax4a,{'Count-derived density','Causal 2 s smoothed density'}, ...
    'Location','northwest','TextColor',fg,'Color',panel,'EdgeColor',muted);
grid(ax4a,'on'); box(ax4a,'on');
densityMax = max(result.density);
set(ax4a,'XLim',[0 durationSec],'YLim',[max(0,min(result.density)-.05), max(3.0,densityMax*1.12)]);
styleDarkAxes(ax4a,fg,muted);
text(ax4a,.985,.10,sprintf('PEAK  %.2f people/m^2',densityMax), ...
    'Units','normalized','HorizontalAlignment','right','Color',cyan, ...
    'FontSize',10,'FontWeight','bold','BackgroundColor',panel,'Margin',5);

ax4b = nexttile(tl4,2); set(ax4b,'Color',panel); hold(ax4b,'on');
plot(ax4b,t(plotIdx),result.densityRate(plotIdx),'Color',orange,'LineWidth',1.7);
yline(ax4b,0,'-','Color',muted,'LineWidth',.8);
ylabel(ax4b,'RATE (people/m^2/s)','Color',orange);
title(ax4b,'SMOOTHED DENSITY RATE — ACTUAL DATA SCALE', ...
    'Color',fg,'FontSize',12,'FontWeight','bold');
grid(ax4b,'on'); box(ax4b,'on');
ratePeak = max(abs(result.densityRate));
rateLimit = max(.004,ratePeak*1.35);
set(ax4b,'XLim',[0 durationSec],'YLim',[-rateLimit rateLimit]);
styleDarkAxes(ax4b,fg,muted);
rateMaxSigned = max(result.densityRate);
text(ax4b,.985,.88,sprintf('REQUIRED RATE LIMIT 0.30  |  OBSERVED MAX +%.4f  |  RATE LIMIT NOT REACHED', ...
    rateMaxSigned),'Units','normalized','HorizontalAlignment','right', ...
    'Color',yellow,'FontSize',9,'FontWeight','bold','BackgroundColor',panel,'Margin',4);

ax4c = nexttile(tl4,3); set(ax4c,'Color',panel); hold(ax4c,'on');
stairs(ax4c,t(plotIdx),double(result.surgeAlarm(plotIdx)),'Color',orange,'LineWidth',1.8);
set(ax4c,'XLim',[0 durationSec],'YLim',[-.08 1.08],'YTick',[0 1], ...
    'YTickLabel',{'NORMAL','ALARM'});
grid(ax4c,'on'); box(ax4c,'on');
xlabel(ax4c,'TIME (s)','Color',fg); ylabel(ax4c,'SURGE STATE','Color',orange);
title(ax4c,'SURGE ALARM STATE (DENSITY OR RATE CONDITION)', ...
    'Color',fg,'FontSize',12,'FontWeight','bold');
styleDarkAxes(ax4c,fg,muted);
text(ax4c,.985,.14,sprintf('ALARM ACTIVE  %.1f%% OF SESSION',100*mean(result.surgeAlarm)), ...
    'Units','normalized','HorizontalAlignment','right','Color',orange, ...
    'FontSize',10,'FontWeight','bold','BackgroundColor',panel,'Margin',5);
saveas(f4,fullfile(outDir,'S1_4_Density_Surge.png'));

fprintf('\n========== S1 PEDESTRIAN FLOW SUMMARY ==========\n');
fprintf('S1-1: a=%.8f, b=%.8f, rise time=%.4f s, settling=%.2f s\n', ...
 result.metrics.pir_a,result.metrics.pir_b, ...
 result.metrics.pir_rise_time_s,result.metrics.pir_settling_time_s);
fprintf('S1-2: ADC step=%.8f V, theoretical SQNR=%.2f dB, error variance=%.4g V^2\n', ...
 result.metrics.adc_step_v,result.metrics.sqnr_db, ...
 result.metrics.quantization_error_variance);
fprintf('S1-3: detected entries=%d, detected exits=%d\n', ...
 result.metrics.total_entries,result.metrics.total_exits);
fprintf('S1-4: peak density=%.4f people/m^2, max smoothed rate=%.5f people/m^2/s, alarm samples=%d\n', ...
 max(result.density),max(result.densityRate),nnz(result.surgeAlarm));
fprintf('Note: with 250 m^2 area and one count per accepted event, the specified 0.30 rate limit may be unreachable; the density limit can still trigger alarms.\n');
fprintf('JSON, CSV, MAT, and four PNG plots saved in:\n%s\n',outDir);
fprintf('To run tests: run(''tests/test_S1.m'')\n');
end

function times = makeEventTimes(tStart,tStop,meanInterval)
% Create reproducible but non-periodic event times within a burst interval.
times = zeros(1,0);
tNow = tStart;
while tNow < tStop
    times(end+1) = tNow;
    tNow = tNow + meanInterval*(.75 + .5*rand());
end
end

function x = paintPulses(x,eventTimes,pulseSamples,Fs,amplitude)
% Draw short sensor pulses without allowing indices past the signal boundary.
N = numel(x);
for k = 1:numel(eventTimes)
    idx = round(eventTimes(k)*Fs)+(1:pulseSamples);
    idx = idx(idx>=1 & idx<=N);
    if ~isempty(idx), x(idx) = amplitude; end
end
end

function styleDarkAxes(ax,fg,gridColor)

set(ax,'FontSize',10,'LineWidth',1.0,'XColor',fg,'YColor',fg, ...
    'GridColor',gridColor,'GridAlpha',0.22,'MinorGridAlpha',0.10, ...
    'Layer','top');
end
