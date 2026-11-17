function test_adversarial()
%TEST_ADVERSARIAL Regression tests for concrete MATLAB/API failure cases.
% This source must be executed in MATLAB before claiming a MATLAB pass.
cfg=songdo.core.defaultConfig();
input=songdo.io.generateScenario(cfg,'temperature_plunge',120);
input.AIR_TEMP_C(2)=24; % Falling integer reading must not saturate its delta.
base=songdo.core.processBlock(input,songdo.core.initState(cfg),cfg);
sensors={'AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_U_MPS','WIND_V_MPS','PRESSURE_HPA'};
for type={'uint16','int16','single'}
    typed=input;
    for k=1:numel(sensors), typed.(sensors{k})=cast(typed.(sensors{k}),type{1}); end
    expected=typed;
    for k=1:numel(sensors), expected.(sensors{k})=double(expected.(sensors{k})); end
    actual=songdo.core.processBlock(typed,songdo.core.initState(cfg),cfg);
    reference=songdo.core.processBlock(expected,songdo.core.initState(cfg),cfg);
    assert(isequaln(actual,reference),'Sensor numeric-class normalization differs.');
    assert(abs(actual.AIR_TEMP_COMP_C(2)-(24-120))<1e-12);
    factor=(1-cfg.lapseRateKPerM*cfg.elevationM/cfg.seaLevelTemperatureK)^ ...
        (-cfg.gravityMPerS2*cfg.molarMassKgPerMol/(cfg.gasConstantJPerMolK*cfg.lapseRateKPerM));
    assert(abs(actual.SEA_LEVEL_PRESSURE_HPA(1)-1012*factor)<1e-10);
end
% Time precision and variable shapes are explicit, never silently discarded.
bad=input; bad.time_s=single(input.time_s);
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
bad=input; bad.time_s(1)=-.1;
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
bad=input; bad.time_s(500)=bad.time_s(500)+1e-4;
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
bad=input; bad.AIR_TEMP_C=[input.AIR_TEMP_C input.AIR_TEMP_C];
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidInput');
bad=input; bad.AIR_TEMP_C=cat(3,input.AIR_TEMP_C,input.AIR_TEMP_C);
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidInput');
bad=input; bad.PRESSURE_HPA=complex(input.PRESSURE_HPA,ones(height(input),1));
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidInput');
bad=input; bad.HUMIDITY_FAULT=cat(3,input.HUMIDITY_FAULT,input.HUMIDITY_FAULT);
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidInput');
% State corruption must fail predictably before processing.
state=songdo.core.initState(cfg);
[~,state]=songdo.core.processBlock(input(1:10,:),state,cfg);
badState=rmfield(state,'tempPoles');
expect(@()songdo.core.processBlock(input(11,:),badState,cfg),'songdo:InvalidState');
badState=state; badState.tempPreviousTime=input.time_s(11);
expect(@()songdo.core.processBlock(input(11,:),badState,cfg),'songdo:InvalidState');
badState=state; badState.windIndex=999;
expect(@()songdo.core.processBlock(input(11,:),badState,cfg),'songdo:InvalidState');
badState=state; badState.humidityCount=0;
expect(@()songdo.core.processBlock(input(11,:),badState,cfg),'songdo:InvalidState');
badState=state; badState.tempPoles(1)=Inf;
expect(@()songdo.core.processBlock(input(11,:),badState,cfg),'songdo:InvalidState');
changed=cfg; changed.windMeanSeconds=20;
expect(@()songdo.core.processBlock(input(11,:),state,changed),'songdo:ConfigChanged');
% Overflowing configuration products are rejected, not exported as GOOD Inf.
badCfg=cfg; badCfg.gravityMPerS2=realmax;
expect(@()songdo.core.initState(badCfg),'songdo:InvalidConfig');
badCfg=cfg; badCfg.tempLowpassHz=realmin;
expect(@()songdo.core.initState(badCfg),'songdo:InvalidConfig');
% Huge finite wind pairs can produce nonfinite scalar speed: invalidate both
% the streaming observation AND its minute contribution consistently.
wind=input(1:600,:); wind.WIND_U_MPS(:)=realmax; wind.WIND_V_MPS(:)=realmax;
out=songdo.core.processBlock(wind,songdo.core.initState(cfg),cfg);
[g,m]=songdo.io.minuteTelemetry(wind,out,cfg);
assert(all(out.WIND_QUALITY=="DROPOUT") && all(isnan(out.WIND_SPEED_MPS)));
assert(m.records.wind_valid_count==0 && isnan(m.records.ws_mps));
assert(isempty(songdo.io.validateTelemetry(g)));
% A huge-but-valid axis vector must not overflow the arithmetic mean sum.
wind.WIND_U_MPS(:)=realmax/2; wind.WIND_V_MPS(:)=0;
out=songdo.core.processBlock(wind,songdo.core.initState(cfg),cfg);
[g,m]=songdo.io.minuteTelemetry(wind,out,cfg);
assert(all(isfinite(out.WIND_MEAN_SPEED_MPS)) && isfinite(m.records.ws_mps));
assert(abs(m.records.ws_mps/(realmax/2)-1)<1e-12);
assert(isempty(songdo.io.validateTelemetry(g)));
% In-range raw spikes can produce impossible compensated estimates.
spike=input(1:600,:); spike.AIR_TEMP_C(1:100)=80; spike.AIR_TEMP_C(101:end)=-80;
spikeOut=songdo.core.processBlock(spike,songdo.core.initState(cfg),cfg);
invalidEstimate=spikeOut.AIR_TEMP_FILTERED_C < -80 | spikeOut.AIR_TEMP_FILTERED_C > 80;
assert(any(invalidEstimate) && all(spikeOut.TEMP_QUALITY(invalidEstimate)=="OUT_OF_RANGE"));
% Leading/all missing data must remain tagged, serializable and recoverable.
missing=input(1:600,:);
for k=1:numel(sensors), missing.(sensors{k})(:)=NaN; end
out=songdo.core.processBlock(missing,songdo.core.initState(cfg),cfg);
[g,m]=songdo.io.minuteTelemetry(missing,out,cfg);
assert(all(strcmp({g.records.quality_flag},'DROPOUT')));
assert(m.records.temperature_good_count==0 && m.records.humidity_good_count==0);
assert(isempty(songdo.io.validateTelemetry(g)));
decoded=jsondecode(jsonencode(g,'ConvertInfAndNaN',true));
assert(isempty(songdo.io.validateTelemetry(decoded)));
% A records matrix encodes nested arrays, which the receiver disallows.
broken=g; broken.records=reshape(g.records,2,2);
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=g; broken.latitude=sparse(37.393);
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=g; broken.records(1).raw_value=sparse(0);
assert(~isempty(songdo.io.validateTelemetry(broken)));
% Replay rejects nonuniform/missing time rows; no hidden interpolation.
folder=tempname; mkdir(folder); clean=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
file=fullfile(folder,'bad.csv'); bad=input; bad(15,:)=[]; writetable(bad,file);
expect(@()songdo.io.readReplay(file,cfg),'songdo:ReplayTime');
bad=input; bad.time_s=(0:height(input)-1)'*0.10000005; writetable(bad,file);
expect(@()songdo.io.readReplay(file,cfg),'songdo:ReplayTime');
expect(@()songdo.core.processBlock(bad,songdo.core.initState(cfg),cfg),'songdo:InvalidTime');
% Incomplete leading/trailing minute bins are omitted, never padded.
partial=input(2:1200,:); out=songdo.core.processBlock(partial,songdo.core.initState(cfg),cfg);
[g,m]=songdo.io.minuteTelemetry(partial,out,cfg);
assert(numel(g.records)==4 && numel(m.records)==1);
assert(strcmp(g.records(1).timestamp,'2026-01-01T00:01:00.000Z'));
assert(songdo.dsp.finiteMean([realmax/2;realmax/2])==realmax/2);
assert(isnan(songdo.dsp.finiteMean([NaN;Inf])));
fprintf('PASS test_adversarial: numeric types, shapes, timing, state, overflow, nulls and minute edges.\n');
end
function expect(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s, got %s.',identifier,err.identifier); return;
end
error('test:MissingFailure','Expected failure %s.',identifier);
end
