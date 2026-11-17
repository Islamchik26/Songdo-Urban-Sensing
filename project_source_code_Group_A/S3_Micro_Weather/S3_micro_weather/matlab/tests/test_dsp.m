function results = test_dsp()
%TEST_DSP Base-MATLAB assertions for causal S3 processing and DSP primitives.
% Run after setup_project, or call directly with this tests folder on path.
% These tests are supplied for execution in MATLAB R2023b+; generating this
% file does not constitute a MATLAB run or hardware validation.
addpath(fileparts(fileparts(mfilename('fullpath'))));
originalRng = rng;
restoreRng = onCleanup(@()rng(originalRng)); %#ok<NASGU>
rng(42,'twister');
cfg = songdo.core.defaultConfig();
checks = strings(0,1);

% Exact sensor recurrence, analytical response, equilibrium and blocks.
x = ones(301,1);
[y,z,model] = songdo.dsp.sensorZoh(x,10,12,1,0);
assert(model.a > 0 && model.a < 1);
assert(max(abs(y-(1-exp(-(0:300)'/120)))) < 5e-14);
assert(abs(z-(model.a*y(end)+model.b)) < 1e-14);
[y1,z1] = songdo.dsp.sensorZoh(x(1:17),10,12,1,0);
[y2,z2] = songdo.dsp.sensorZoh(x(18:end),10,12,1,z1);
assert(isequal(y,[y1;y2]) && z == z2);
yEq = songdo.dsp.sensorZoh(30*ones(100,1),10,12,1,30);
assert(max(abs(yEq-30)) < 1e-12);
checks(end+1) = "ZOH analytical stability, equilibrium and streaming";

% Nonzero temperature startup and explicit prescribed compensation oracle.
in = fixture(431,cfg);
in.AIR_TEMP_C = 24+0.05*sin(2*pi*0.1*in.time_s);
[whole,state] = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
expectedComp = [in.AIR_TEMP_C(1);in.AIR_TEMP_C(2:end)+ ...
    cfg.tempTauSeconds*cfg.fsHz*diff(in.AIR_TEMP_C)];
a = exp(-2*pi*cfg.tempLowpassHz/cfg.fsHz);
expected = expectedComp;
for k = 1:3
    expected = filter(1-a,[1 -a],expected,a*in.AIR_TEMP_C(1));
end
assert(max(abs(whole.AIR_TEMP_COMP_C-expectedComp)) < 1e-10);
assert(max(abs(whole.AIR_TEMP_FILTERED_C-expected)) < 1e-10);
assert(whole.AIR_TEMP_FILTERED_C(1) == in.AIR_TEMP_C(1));
checks(end+1) = "Prescribed compensation and initialized three-pole oracle";

% Arbitrary block boundaries, including one-sample and empty blocks.
streamState = songdo.core.initState(cfg);
stream = whole([],:);
starts = [1 2 19 80 81 215 401 432];
for k = 1:numel(starts)-1
    rows = starts(k):starts(k+1)-1;
    [part,streamState] = songdo.core.processBlock(in(rows,:),streamState,cfg);
    stream = [stream;part]; %#ok<AGROW>
end
assert(isequaln(stream,whole));
assert(isequaln(streamState,state));
[empty,emptyState] = songdo.core.processBlock(in([],:),state,cfg);
assert(height(empty) == 0 && isequaln(emptyState,state));
changedFuture = in;
changedFuture.AIR_TEMP_C(201:end) = 10;
changedFuture.REL_HUMIDITY_PCT(201:end) = 75;
changedFuture.WIND_U_MPS(201:end) = -20;
changedFuture.PRESSURE_HPA(201:end) = 1000;
causal = songdo.core.processBlock(changedFuture,songdo.core.initState(cfg),cfg);
assert(isequaln(causal(1:200,:),whole(1:200,:)));
checks(end+1) = "Whole-record/block identity, empty blocks and causality";

% Temperature missing-value state freeze and elapsed-time gap derivative.
in = fixture(8,cfg);
in.AIR_TEMP_C = [20;NaN;NaN;20.3;20.4;-90;20.6;20.7];
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(out.TEMP_QUALITY(2) == "DROPOUT");
assert(out.TEMP_QUALITY(6) == "OUT_OF_RANGE");
assert(out.AIR_TEMP_FILTERED_C(2) == 20 && out.AIR_TEMP_FILTERED_C(3) == 20);
assert(abs(out.AIR_TEMP_COMP_C(4)-(20.3+12/0.3*0.3)) < 1e-10);
assert(abs(out.AIR_TEMP_COMP_C(7)-(20.6+12/0.2*0.2)) < 1e-10);
assert(all(isfinite(out.AIR_TEMP_FILTERED_C)));
checks(end+1) = "Temperature dropout holds and elapsed-time derivative recovery";

% Uniform timestamps both within and across blocks are mandatory.
in = fixture(10,cfg);
bad = in; bad.time_s(4) = bad.time_s(3);
expectError(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
bad = in; bad.time_s(4) = bad.time_s(4)+0.02;
expectError(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
bad = in; bad.time_s(4) = NaN;
expectError(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
[~,prior] = songdo.core.processBlock(in(1:5,:),songdo.core.initState(cfg),cfg);
expectError(@()songdo.core.processBlock(in(7:10,:),prior,cfg),'songdo:InvalidTime');
badCfg = cfg; badCfg.tempGain = 2;
expectError(@()songdo.core.initState(badCfg),'songdo:InvalidConfig');
newCfg = cfg; newCfg.tempLowpassHz = 0.3;
[tunedRows,tuned] = songdo.core.processBlock(in(6:10,:),prior,newCfg);
assert(tuned.sampleCount == 10 && tuned.lastTimeSeconds == in.time_s(10));
assert(all(tunedRows.TEMP_CUTOFF_HZ == newCfg.tempLowpassHz));
assert(all(tunedRows.AIR_TEMP_FILTERED_C == 25));
assert(tuned.windCount == 10 && tuned.config.tempLowpassHz == 0.3);
checks(end+1) = "Time validation, fixed sensor gain and live cutoff tuning";

% Humidity raw-slot median, rate validation, dropout and legitimate endpoints.
in = fixture(12,cfg);
in.REL_HUMIDITY_PCT = [50;50;50;50;50;90;50;0;100;NaN;50;50];
in.HUMIDITY_FAULT = false(height(in),1);
in.HUMIDITY_FAULT([8 9]) = true;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(all(out.REL_HUMIDITY_FILTERED_PCT == 50));
assert(all(out.HUMIDITY_QUALITY([8 9 10]) == "DROPOUT"));
assert(all(out.HUMIDITY_QUALITY([1:7 11 12]) == "GOOD"));
for endpoint = [0 100]
    in = fixture(5,cfg); in.REL_HUMIDITY_PCT(:) = endpoint;
    out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
    assert(all(out.HUMIDITY_QUALITY == "GOOD"));
    assert(all(out.REL_HUMIDITY_FILTERED_PCT == endpoint));
end
in = fixture(110,cfg); in.REL_HUMIDITY_PCT(6:end) = 70;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(any(out.HUMIDITY_QUALITY == "SUSPECT_JUMP"));
assert(out.HUMIDITY_QUALITY(end) == "GOOD");
% Important: this is accepted-observation-rate validation, not a slew limiter.
assert(any(diff(out.REL_HUMIDITY_FILTERED_PCT) > 2/cfg.fsHz));
in = fixture(8,cfg); in.REL_HUMIDITY_PCT(2:6) = NaN;
in.REL_HUMIDITY_PCT(7:8) = 50.6;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(out.HUMIDITY_QUALITY(7) == "GOOD");
assert(abs(out.REL_HUMIDITY_FILTERED_PCT(7)-50.6) < 1e-12);
checks(end+1) = "Humidity median, fault endpoints and accepted-observation rate";

% Vector mean, wraparound, calm, gust length and partial-window disclosure.
in = fixture(200,cfg);
in.WIND_U_MPS(:) = 3; in.WIND_V_MPS(:) = 4;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(max(abs(out.WIND_SPEED_MPS-5)) < 1e-12);
assert(max(abs(out.WIND_MEAN_SPEED_MPS-5)) < 1e-12);
assert(max(abs(out.WIND_MEAN_DIR_DEG-atan2d(3,4))) < 1e-12);
assert(~any(out.WIND_WINDOW_COMPLETE(1:99)) && all(out.WIND_WINDOW_COMPLETE(100:end)));
in.WIND_U_MPS = repmat([1;-1],100,1); in.WIND_V_MPS(:) = 10;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(abs(out.WIND_MEAN_DIR_DEG(100)) < 1e-12);
in.WIND_U_MPS(:) = 0; in.WIND_V_MPS(:) = 0;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(all(isnan(out.WIND_MEAN_DIR_DEG)) && all(out.WIND_MEAN_SPEED_MPS == 0));
in.WIND_U_MPS(:) = 1; in.WIND_V_MPS(:) = 0; in.WIND_U_MPS(1) = 9;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(all(out.WIND_GUST_MPS(1:30) == 9) && out.WIND_GUST_MPS(31) == 1);
in.WIND_U_MPS(20) = NaN;
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
assert(all(out.WIND_QUALITY(20:119) == "DROPOUT"));
assert(out.WIND_QUALITY(120) == "GOOD" && out.WIND_WINDOW_COMPLETE(120));
checks(end+1) = "Vector wind means, calm, 30-slot gust and invalid-window aging";

% Source sea-level pressure formula and unit convention (hPa in, hPa out).
in = fixture(3,cfg); in.PRESSURE_HPA = [1012;NaN;100];
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
factor = (1-cfg.lapseRateKPerM*cfg.elevationM/cfg.seaLevelTemperatureK)^ ...
    (-cfg.gravityMPerS2*cfg.molarMassKgPerMol/(cfg.gasConstantJPerMolK*cfg.lapseRateKPerM));
assert(abs(out.SEA_LEVEL_PRESSURE_HPA(1)-1012*factor) < 1e-10);
assert(out.SEA_LEVEL_PRESSURE_HPA(1) > 1012);
assert(out.PRESSURE_QUALITY(2) == "DROPOUT" && out.PRESSURE_QUALITY(3) == "OUT_OF_RANGE");
checks(end+1) = "Pressure formula, units and invalid-value flags";

% A clean sudden 5 C plunge: t50 delay vs true step, not a rise-time proxy.
in = fixture(1000,cfg); trueT = 30*ones(height(in),1); trueT(in.time_s >= 10) = 25;
in.AIR_TEMP_C = songdo.dsp.sensorZoh(trueT,cfg.fsHz,12,1,30);
out = songdo.core.processBlock(in,songdo.core.initState(cfg),cfg);
rawDelay = crossingTime(in.time_s,in.AIR_TEMP_C,27.5,10)-10;
filteredDelay = crossingTime(in.time_s,out.AIR_TEMP_FILTERED_C,27.5,10)-10;
reduction = 1-filteredDelay/rawDelay;
assert(reduction >= 0.65,'Clean default t50 delay reduction is below 65%%.');
checks(end+1) = "Default noiseless plunge achieves defined t50 delay reduction";

% Hann coherent gain including DC/Nyquist and odd record lengths.
for n = [1000 1001]
    t = (0:n-1)'/1000; bin = 37; frequency = bin*1000/n;
    [f,amp] = songdo.dsp.oneSidedSpectrum(2.3*sin(2*pi*frequency*t),1000);
    assert(abs(f(bin+1)-frequency) < 1e-10);
    assert(abs(amp(bin+1)-2.3) < 1e-12);
end
[~,amp] = songdo.dsp.oneSidedSpectrum(3*ones(1000,1),1000);
assert(abs(amp(1)-3) < 1e-12);
[~,amp] = songdo.dsp.oneSidedSpectrum(1.7*(-1).^(0:999)',1000);
assert(abs(amp(end)-1.7) < 1e-12);
expectError(@()songdo.dsp.oneSidedSpectrum([1 NaN 3],10),'');
checks(end+1) = "Hann amplitude scaling for tones, DC, Nyquist and odd lengths";

% ADC noise variance (uniform input) and full-scale sine SQNR.
x = 2*rand(200000,1)-1;
[q,delta,meta] = songdo.dsp.quantizeSignal(x,8,[-1 1]);
varianceRatio = mean((q-x).^2)/(delta^2/12);
assert(abs(varianceRatio-1) < 0.02 && ~any(meta.clipped));
x = sin(2*pi*997*(0:199999)'/200000);
[q,~,meta] = songdo.dsp.quantizeSignal(x,12,[-1 1]);
sqnr = 10*log10(mean(x.^2)/mean((q-x).^2));
assert(abs(sqnr-meta.fullScaleSineSqnrDb) < 0.35);
[q,~,meta] = songdo.dsp.quantizeSignal([-2 -1 0 1 2 NaN],3,[-1 1]);
assert(q(1) == -0.875 && q(5) == 0.875 && isnan(q(6)));
assert(isequal(meta.clipped,[true false false false true false]));
checks(end+1) = "Midrise ADC saturation, noise variance and full-scale sine SQNR";

% FIR symmetry/linear phase and explicit streaming filter state retention.
h = songdo.dsp.firWindowedSinc(31,1,10);
assert(max(abs(h-fliplr(h))) < 1e-14 && abs(sum(h)-1) < 1e-14);
omega = linspace(0,0.4*pi,100)';
response = exp(-1i*omega*(0:30))*h(:);
zeroPhase = response.*exp(1i*omega*15);
assert(max(abs(imag(zeroPhase))) < 1e-12);
x = randn(300,1); batch = filter(h,1,x);
[p1,z1] = filter(h,1,x(1:73),zeros(numel(h)-1,1));
p2 = filter(h,1,x(74:end),z1);
assert(max(abs(batch-[p1;p2])) < 1e-12);
checks(end+1) = "Symmetric linear-phase FIR and explicit zi/zf continuity";

[latch,z] = songdo.dsp.hysteresis([0 2 1.5 1.1 NaN 1 1.8 2],1,2,false);
assert(isequal(latch,logical([0 1 1 1 1 0 0 1])) && z);
[l1,z1] = songdo.dsp.hysteresis([0 2 1.5],1,2,false);
l2 = songdo.dsp.hysteresis([1.1 NaN 1 1.8 2],1,2,z1);
assert(isequal(latch,[l1 l2]));
checks(end+1) = "Dual-threshold hysteresis and block state";

radius = 6371008.8;
assert(songdo.dsp.haversine(37.393,126.6345,37.393,126.6345) == 0);
assert(abs(songdo.dsp.haversine(0,0,0,90)-pi*radius/2) < 1e-7);
assert(abs(songdo.dsp.haversine(0,0,0,180)-pi*radius) < 1e-7);
assert(abs(songdo.dsp.haversine(0,179,0,-179)-deg2rad(2)*radius) < 1e-7);
checks(end+1) = "Haversine coincident, quarter-circle, antipodal and dateline cases";

results = struct('name','S3 core and DSP','passed',true,'checks',numel(checks), ...
    'details',checks,'rawT50DelaySeconds',rawDelay, ...
    'filteredT50DelaySeconds',filteredDelay,'delayReductionFraction',reduction, ...
    'quantizationVarianceRatio',varianceRatio,'sqnrDb',sqnr);
fprintf('test_dsp: %d groups passed. Clean t50 delay reduction: %.1f%%.\n',numel(checks),100*reduction);
end

function input = fixture(n,cfg)
time_s = (0:n-1)'/cfg.fsHz;
AIR_TEMP_C = 25*ones(n,1);
REL_HUMIDITY_PCT = 50*ones(n,1);
WIND_U_MPS = 2*ones(n,1);
WIND_V_MPS = 3*ones(n,1);
PRESSURE_HPA = 1012*ones(n,1);
input = table(time_s,AIR_TEMP_C,REL_HUMIDITY_PCT,WIND_U_MPS,WIND_V_MPS,PRESSURE_HPA);
end

function expectError(action,identifier)
caught = false;
try
    action();
catch exception
    caught = true;
    if ~isempty(identifier)
        assert(strcmp(exception.identifier,identifier), ...
            'Expected %s, got %s.',identifier,exception.identifier);
    end
end
assert(caught,'Expected the operation to fail.');
end

function time = crossingTime(t,y,threshold,after)
% Linearly interpolate the first descending threshold crossing after step.
k = find(t >= after & y <= threshold,1);
assert(~isempty(k) && k > 1,'Expected a descending threshold crossing.');
assert(y(k-1) > threshold,'Expected samples bracketing the threshold.');
fraction = (threshold-y(k-1))/(y(k)-y(k-1));
time = t(k-1)+fraction*(t(k)-t(k-1));
end
