function validateState(state,cfg)
%VALIDATESTATE Reject malformed/corrupted streaming state before mutation.
fields={'version','sampleCount','lastTimeSeconds','startTimeSeconds','config','tempPreviousRaw', ...
    'tempPreviousTime','tempPoles','tempInitialized','humidityRaw', ...
    'humidityIndex','humidityCount','humidityAccepted','humidityAcceptedTime', ...
    'windCapacity','windU','windV','windScalarSpeed','windIndex','windCount'};
if ~isstruct(state)||~isscalar(state)||~all(isfield(state,fields)) || ...
        ~scalarInteger(state.version,1,1) || ~isstruct(state.config)||~isscalar(state.config)
    fail();
end
% Validate the state against the configuration that created its buffers.
% The caller separately rejects reset-requiring changes to the new config.
try
    cfg=songdo.dsp.validateConfig(state.config);
catch
    fail();
end
if ~scalarInteger(state.sampleCount,0,flintmax) || ...
        ~scalarInteger(state.humidityIndex,0,cfg.humidityMedianSamples) || ...
        ~scalarInteger(state.humidityCount,0,cfg.humidityMedianSamples)
    fail();
end
capacity=max(round(cfg.windMeanSeconds*cfg.fsHz),round(cfg.windGustSeconds*cfg.fsHz));
if ~scalarInteger(state.windCapacity,capacity,capacity) || ...
        ~scalarInteger(state.windIndex,0,capacity)||~scalarInteger(state.windCount,0,capacity)
    fail();
end
arrays={'tempPoles','humidityRaw','windU','windV','windScalarSpeed'};
lengths=[cfg.tempLowpassPoles cfg.humidityMedianSamples capacity capacity capacity];
for k=1:numel(arrays)
    x=state.(arrays{k});
    if ~isa(x,'double')||issparse(x)||~isreal(x)||~isequal(size(x),[lengths(k),1])||any(isinf(x)), fail(); end
end
for key={'lastTimeSeconds','startTimeSeconds','tempPreviousRaw','tempPreviousTime','humidityAccepted','humidityAcceptedTime'}
    x=state.(key{1});
    if ~isa(x,'double')||~isscalar(x)||~isreal(x)||isinf(x), fail(); end
end
if ~islogical(state.tempInitialized)||~isscalar(state.tempInitialized), fail(); end
if state.tempInitialized && (~isfinite(state.tempPreviousRaw)||~isfinite(state.tempPreviousTime)||any(~isfinite(state.tempPoles)))
    fail();
end
if xor(isfinite(state.humidityAccepted),isfinite(state.humidityAcceptedTime)), fail(); end
if state.humidityCount~=min(state.sampleCount,cfg.humidityMedianSamples) || ...
        state.windCount~=min(state.sampleCount,capacity)
    fail();
end
if state.sampleCount==0
    if ~isnan(state.lastTimeSeconds)||~isnan(state.startTimeSeconds)||state.windCount~=0||state.humidityCount~=0||state.windIndex~=0||state.humidityIndex~=0, fail(); end
else
    if ~isfinite(state.lastTimeSeconds)||~isfinite(state.startTimeSeconds)|| ...
            state.startTimeSeconds<0||state.startTimeSeconds>state.lastTimeSeconds|| ...
            state.windIndex~=mod(state.sampleCount-1,capacity)+1 || ...
            state.humidityIndex~=mod(state.sampleCount-1,cfg.humidityMedianSamples)+1, fail(); end
    if abs(state.lastTimeSeconds-(state.startTimeSeconds+(state.sampleCount-1)/cfg.fsHz))>1e-8, fail(); end
    if state.tempInitialized && (state.tempPreviousTime>state.lastTimeSeconds || state.tempPreviousTime<state.startTimeSeconds), fail(); end
    if isfinite(state.humidityAcceptedTime) && (state.humidityAcceptedTime>state.lastTimeSeconds || state.humidityAcceptedTime<state.startTimeSeconds), fail(); end
end
fixed={'fsHz','tempTauSeconds','tempGain','tempLowpassPoles','windMeanSeconds','windGustSeconds','humidityMedianSamples'};
if ~all(isfield(state.config,fixed)), fail(); end
end
function yes=scalarInteger(x,low,high)
yes=isa(x,'double')&&isreal(x)&&isscalar(x)&&isfinite(x)&&x==fix(x)&&x>=low&&x<=high;
end
function fail()
error('songdo:InvalidState','Streaming state is invalid; create a fresh state with songdo.core.initState(cfg).');
end
