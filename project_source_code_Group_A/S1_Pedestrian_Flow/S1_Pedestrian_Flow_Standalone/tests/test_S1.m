% Run from package root with: tests/test_S1
clear; clc; fprintf('Running Team S1 tests...\n');
Fs=200; tau=.8; K=2.5; a=exp(-1/(Fs*tau)); b=K*(1-a);
assert(abs(a-.99376949)<1e-6,'S1-1 coefficient a mismatch.');
assert(abs(b-.0155763)<1e-5,'S1-1 coefficient b mismatch.');
assert(abs(tau*log(9)-1.7578)<.002,'S1-1 rise-time formula mismatch.');
assert(abs(4*tau-3.2)<eps,'S1-1 settling time mismatch.');
fprintf(' PASS S1-1 model constants and analytical response times\n');

t=(0:1/Fs:10-1/Fs)'; N=numel(t);
pirInput=double(t>=1); pressure=min(max(1.65+.4*sin(2*pi*3*t)+.2*sin(2*pi*65*t),0),3.3);
delta=zeros(N,1);
delta(round(1*Fs)+(1:20))=1; delta(round(2*Fs)+(1:5))=1;
delta(round(3*Fs)+(1:20))=1; delta(round(4*Fs)+(1:20))=-1;
r=s1_process(t,pirInput,pressure,delta,Fs);
assert(numel(r.pirOutput)==N && all(isfinite(r.pirOutput)),'S1-1 output invalid.');
assert(abs(r.pirOutput(end)-K)<.02,'PIR step did not approach K.');
fprintf(' PASS S1-1 discrete step response\n');

q=3.3/4096;
assert(abs(r.metrics.adc_step_v-q)<1e-12,'ADC step mismatch.');
assert(abs(r.metrics.sqnr_db-74)<.02,'SQNR mismatch.');
assert(all(r.pressureQuantized>=0&r.pressureQuantized<=3.3),'ADC outside range.');
assert(abs(r.pressureFiltered(1)-pressure(1))<.15,'Causal filter initial steady state is not initialized.');
assert(max(abs(r.quantizationError))<=q/2+1e-10,'Quantization error exceeds half LSB.');
fprintf(' PASS S1-2 filtering, ADC range, quantization bound, SQNR\n');

assert(sum(r.entryEvent)==2,'Expected two valid entries; short chatter should be ignored.');
assert(sum(r.exitEvent)==1,'Expected one valid exit.');
fprintf(' PASS S1-3 duration-qualified hysteresis and event counts\n');

assert(all(abs(r.density-r.netCount/250)<1e-12),'Density must equal net count / 250.');
assert(numel(r.densityRate)==N&&all(isfinite(r.densityRate)),'Derivative invalid.');
assert(numel(r.densitySmoothed)==N&&all(isfinite(r.densitySmoothed)),'Smoothed density invalid.');
assert(r.metrics.density_rate_smoothing_seconds==2,'Density-rate smoothing window mismatch.');
assert(all(r.surgeAlarm==(r.density>2.5|r.densityRate>.3)),'Alarm logic mismatch.');
fprintf(' PASS S1-4 density, derivative and alarm logic\n');

tmp=tempname; mkdir(tmp); jp=fullfile(tmp,'test.json'); cp=fullfile(tmp,'test.csv');
s1_export(r,jp,cp); packet=jsondecode(fileread(jp));
assert(strcmp(packet.schema_version,'1.0'),'Schema version mismatch.');
assert(strcmp(packet.station_id,'STATION_CONVENSIA'),'Station mismatch.');
assert(abs(packet.latitude-37.3888)<1e-6&&abs(packet.longitude-126.6534)<1e-6,'Coordinates mismatch.');
assert(~isempty(packet.records)&&strcmp(packet.records(1).channel,'PED_PIR_COUNT'),'Missing records/channel.');
assert(isfile(cp)&&contains(fileread(cp),'quality_flag'),'CSV missing or lacks quality flag.');
rmdir(tmp,'s'); fprintf(' PASS S1-5 JSON/CSV export schema\n');
fprintf('\nAll standalone S1 tests passed.\n');
