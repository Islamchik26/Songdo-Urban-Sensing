function input = generateScenario(cfg, scenario, durationSeconds)
%GENERATESCENARIO Reproducible synthetic S3 observations, not KMA observations.
% mixed: 100-Hz physical model -> sensor -> analog lowpass -> 10-Hz ADC -> faults.
% temperature_plunge: clean exact-ZOH reference at 10 Hz, no analog/ADC noise.
if nargin < 1 || isempty(cfg), cfg = songdo.core.defaultConfig(); end
if nargin < 2 || isempty(scenario), scenario = cfg.scenario; end
if nargin < 3 || isempty(durationSeconds), durationSeconds = cfg.durationSeconds; end
validateattributes(durationSeconds, {'numeric'}, {'scalar','real','finite','positive'});
if cfg.fsHz ~= 10, error('songdo:WindRate','The S3 wind contract requires 10 Hz.'); end
N = round(durationSeconds*cfg.fsHz);
if N < 2 || abs(N-durationSeconds*cfg.fsHz)>1e-8
    error('songdo:Duration','Duration must contain an integer number of samples.');
end
previousRng = rng; restoreRng = onCleanup(@()rng(previousRng)); %#ok<NASGU>
rng(cfg.seed,'twister');
t = (0:N-1)'/cfg.fsHz;
scenario = lower(string(scenario));
if scenario == "temperature_plunge"
    truthT = 25 - 5*(t >= 30);
    a = exp(-1/(cfg.fsHz*cfg.tempTauSeconds));
    air = zeros(N,1); air(1) = cfg.tempGain*truthT(1);
    for k=2:N
        air(k) = a*air(k-1) + cfg.tempGain*(1-a)*truthT(k-1);
    end
    truthH = 65*ones(N,1); humidity = truthH;
    u = 2*ones(N,1); v = 3*ones(N,1); pressure = 1012*ones(N,1);
elseif scenario == "mixed"
    os = cfg.analogOversample; fHi = cfg.fsHz*os;
    th = (0:N*os-1)'/fHi;
    truthTH = 25 - 5*(th>=30) + 0.3*sin(2*pi*th/240);
    truthHH = 65 + 2*sin(2*pi*th/180);
    a = exp(-1/(fHi*cfg.tempTauSeconds));
    sensed = zeros(size(th)); sensed(1) = cfg.tempGain*truthTH(1);
    for k=2:numel(th)
        sensed(k) = a*sensed(k-1) + cfg.tempGain*(1-a)*truthTH(k-1);
    end
    gust = 6*((th>=80)&(th<82));
    uH = 2 + 0.5*sin(2*pi*th/40) + gust;
    vH = 3 + 0.4*cos(2*pi*th/55);
    pH = 1012 + 0.4*sin(2*pi*th/300);
    values = [sensed+0.025*randn(size(th)), truthHH+0.15*randn(size(th)), ...
              uH+0.08*randn(size(th)),vH+0.08*randn(size(th)),pH+0.02*randn(size(th))];
    % Explicit analog-conditioning approximation at an oversampled rate.
    aa = exp(-2*pi*cfg.analogCutoffHz/fHi);
    values = filter(1-aa,[1 -aa],values,aa*values(1,:),1);
    values = values(1:os:end,:);
    ranges = [-40 60;0 100;-40 40;-40 40;800 1100];
    for c=1:5
        values(:,c) = songdo.dsp.quantizeSignal(values(:,c),cfg.adcBits,ranges(c,:));
    end
    air=values(:,1); humidity=values(:,2); u=values(:,3); v=values(:,4); pressure=values(:,5);
    truthT=truthTH(1:os:end); truthH=truthHH(1:os:end);
else
    error('songdo:Scenario','Supported scenarios: mixed or temperature_plunge.');
end
fault = false(N,1);
if scenario == "mixed"
    % Marker differentiates salt-mist transients from legitimate 0/100% RH.
    ix=find(t>=45 & t<45.2); humidity(ix)=0; fault(ix)=true;
    ix=find(t>=65 & t<65.1); humidity(ix)=100; fault(ix)=true;
    humidity(t>=105 & t<105.3)=NaN;
    humidity(t>=115 & t<115.1)=92;  % isolated electromagnetic spike
    humidity(t>=130 & t<135)=humidity(t>=130 & t<135)+15; % sustained suspect step
end
input=table(t,air,humidity,u,v,pressure,fault,truthT,truthH, ...
    'VariableNames',{'time_s','AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_U_MPS', ...
    'WIND_V_MPS','PRESSURE_HPA','HUMIDITY_FAULT','TRUE_AIR_TEMP_C','TRUE_REL_HUMIDITY_PCT'});
input.Properties.UserData=struct('provenance','SYNTHETIC','scenario',char(scenario), ...
    'seed',cfg.seed,'startUtc',cfg.startUtc,'analogOversample',cfg.analogOversample);
end
