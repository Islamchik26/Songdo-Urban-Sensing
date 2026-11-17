function state = initState(cfg)
%INITSTATE Create resettable causal S3 processing state.
% All history is private to this returned structure, not a persistent global.
cfg = songdo.dsp.validateConfig(cfg);
state.version = 1;
state.sampleCount = 0;
state.lastTimeSeconds = NaN;
state.startTimeSeconds = NaN;
state.config = cfg;
state.tempPreviousRaw = NaN;
state.tempPreviousTime = NaN;
state.tempPoles = nan(cfg.tempLowpassPoles,1);
state.tempInitialized = false;
state.humidityRaw = nan(cfg.humidityMedianSamples,1);
state.humidityIndex = 0;
state.humidityCount = 0;
state.humidityAccepted = NaN;
state.humidityAcceptedTime = NaN;
state.windCapacity = max(round(cfg.windMeanSeconds*cfg.fsHz), ...
    round(cfg.windGustSeconds*cfg.fsHz));
state.windU = nan(state.windCapacity,1);
state.windV = nan(state.windCapacity,1);
state.windScalarSpeed = nan(state.windCapacity,1);
state.windIndex = 0;
state.windCount = 0;
end
