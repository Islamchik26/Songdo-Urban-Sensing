function result = s1_process(t,pirInput,pressureRaw,deltaV,Fs)
% S1_PROCESS Implements Team S1 scenarios S1-1 through S1-4.
% S1-5 export is handled by s1_export.m. Filtering is causal (no FILTFILT).
assert(numel(t)==numel(pirInput) && numel(t)==numel(pressureRaw) && numel(t)==numel(deltaV), ...
 'All input vectors must have equal lengths.');
assert(numel(t)>=5 && Fs>80,'Need at least five samples and Fs > 2*40 Hz.');
assert(all(isfinite(t)) && all(isfinite(pirInput)) && all(isfinite(pressureRaw)) && all(isfinite(deltaV)), ...
 'Inputs must be finite.');
t=t(:); pirInput=pirInput(:); pressureRaw=pressureRaw(:); deltaV=deltaV(:); N=numel(t);

% S1-1: tau*dy/dt + y = K*x; zero-order hold discretization.
tau=.8; K=2.5; a=exp(-1/(Fs*tau)); b=K*(1-a); pirOutput=zeros(N,1);
for n=2:N, pirOutput(n)=a*pirOutput(n-1)+b*pirInput(n-1); end

% S1-2: 2nd-order Butterworth low-pass, bilinear transform, pre warped at 40 Hz.
fc=40; k=tan(pi*fc/Fs); den=1+sqrt(2)*k+k^2;
bAA=[k^2 2*k^2 k^2]/den;
aAA=[1 2*(k^2-1)/den (1-sqrt(2)*k+k^2)/den];
% Warm the causal filter with the first measured level, then discard the
% pre-roll. This initializes the filter near steady state and avoids an
% artificial zero-to-baseline jump at t=0 in both processing and plots.
warmupN=max(10,ceil(.25*Fs));
preRoll=repmat(pressureRaw(1),warmupN,1);
filteredWarm=filter(bAA,aAA,[preRoll; pressureRaw]);
pressureFiltered=filteredWarm(warmupN+1:end);
VFS=3.3; bits=12; q=VFS/(2^bits);
adcCode=min(max(round(pressureFiltered/q),0),2^bits-1);
pressureQuantized=adcCode*q; quantError=pressureQuantized-pressureFiltered;
sqnrDb=6.02*bits+1.76;

% S1-3: positive pulses count entries, negative pulses count exits.
% Require 15 consecutive samples above +/-0.75 V; re-arm inside +/-0.20 V.
[entryEvent,exitEvent]=hysteresis_events(deltaV,.75,.20,15);
entryCount=cumsum(entryEvent); exitCount=cumsum(exitEvent); netCount=entryCount-exitCount;

% S1-4: density over 250 m^2. A causal 2 s moving average is used before
% differentiation; differentiating the raw staircase creates one-sample spikes
% at every count update and makes the rate plot unreadable. This remains causal.
areaM2=250; density=netCount/areaM2;
rateWindowSec=2.0; rateWindowSamples=max(5,round(rateWindowSec*Fs));
densitySmoothed=filter(ones(rateWindowSamples,1)/rateWindowSamples,1,density);
densityRate=zeros(N,1);
if N>=5
 densityRate(1)=Fs*(densitySmoothed(2)-densitySmoothed(1));
 densityRate(2)=Fs*(densitySmoothed(3)-densitySmoothed(1))/2;
 for n=3:N-2
  densityRate(n)=Fs*(densitySmoothed(n-2)-8*densitySmoothed(n-1)+ ...
      8*densitySmoothed(n+1)-densitySmoothed(n+2))/12;
 end
 densityRate(N-1)=Fs*(densitySmoothed(N)-densitySmoothed(N-2))/2;
 densityRate(N)=Fs*(densitySmoothed(N)-densitySmoothed(N-1));
end
surgeAlarm=(density>2.5)|(densityRate>0.3);

% S1-5 metadata and quality tags consumed by exporter.
qualityFlag=repmat("GOOD",N,1); qualityFlag(adcCode==0|adcCode==2^bits-1)="CHECK";
result=struct('time',t,'sampleRateHz',Fs,'stationId','STATION_CONVENSIA', ...
 'latitude',37.3888,'longitude',126.6534,'pirInput',pirInput,'pirOutput',pirOutput, ...
 'pressureRaw',pressureRaw,'pressureFiltered',pressureFiltered,'pressureQuantized',pressureQuantized, ...
 'quantizationError',quantError,'deltaV',deltaV,'entryEvent',entryEvent,'exitEvent',exitEvent, ...
 'entryCount',entryCount,'exitCount',exitCount,'netCount',netCount,'density',density, ...
 'densitySmoothed',densitySmoothed,'densityRate',densityRate, ...
 'surgeAlarm',surgeAlarm,'qualityFlag',qualityFlag);
result.metrics=struct('pir_a',a,'pir_b',b,'pir_rise_time_s',tau*log(9), ...
 'pir_settling_time_s',4*tau,'adc_step_v',q,'sqnr_db',sqnrDb, ...
 'quantization_error_variance',var(quantError,1),'quantization_theory_variance',q^2/12, ...
 'total_entries',sum(entryEvent),'total_exits',sum(exitEvent),'anti_alias_b',bAA, ...
 'anti_alias_a',aAA,'area_m2',areaM2,'density_rate_smoothing_seconds',rateWindowSec, ...
 'surge_density_threshold',2.5,'surge_rate_threshold',.3);
end

function [entryEvent,exitEvent]=hysteresis_events(x,high,low,minDuration)
N=numel(x); entryEvent=false(N,1); exitEvent=false(N,1);
armed=true; positiveRun=0; negativeRun=0;
for n=1:N
 if ~armed
  if abs(x(n))<=low, armed=true; positiveRun=0; negativeRun=0; end
  continue;
 end
 if x(n)>=high
  positiveRun=positiveRun+1; negativeRun=0;
  if positiveRun>=minDuration, entryEvent(n)=true; armed=false; positiveRun=0; end
 elseif x(n)<=-high
  negativeRun=negativeRun+1; positiveRun=0;
  if negativeRun>=minDuration, exitEvent(n)=true; armed=false; negativeRun=0; end
 else
  positiveRun=0; negativeRun=0;
 end
end
end
