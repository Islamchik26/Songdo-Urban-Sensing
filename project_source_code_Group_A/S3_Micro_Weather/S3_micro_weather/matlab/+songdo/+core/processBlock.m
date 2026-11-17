function [out,state] = processBlock(input,state,cfg)
%PROCESSBLOCK Strictly causal S3 micro-weather signal processing.
% Time is uniform at 10 Hz, including rows whose sensor values are invalid.
% Temperature: prescribed backward difference followed by three causal poles.
% A missing temperature freezes its state; the next derivative uses elapsed
% time since the last valid sample. This recovery rule avoids a gap spike.
% Humidity median uses valid values in the latest five RAW TIME SLOTS, not
% the latest five accepted values. Invalid current readings hold the last
% accepted output and carry a bad quality flag. Rejected medians do not move
% the rate-check reference. Neither endpoint (0 or 100) is invalid by itself.
% Wind direction is the supplied atan2d(mean(u),mean(v)), wrapped to [0,360),
% not a meteorological 'from' conversion. Calm direction is undefined (NaN).
% Bounds and the calm threshold are engineering assumptions in the config.
cfg = songdo.dsp.validateConfig(cfg);
validateInput(input,state,cfg);
% MATLAB integer arithmetic saturates. Normalize sensor columns before any
% differences, hypot, filters, pressure multiplication or averaging.
for key={'AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_U_MPS','WIND_V_MPS','PRESSURE_HPA'}
    input.(key{1})=full(double(input.(key{1})));
end
if ismember('HUMIDITY_FAULT',input.Properties.VariableNames)
    input.HUMIDITY_FAULT=full(logical(input.HUMIDITY_FAULT));
end
out = input;
n = height(input);
comp = nan(n,1); temp = nan(n,1); tq = strings(n,1);
rh = nan(n,1); hq = strings(n,1);
speed = nan(n,1); meanSpeed = nan(n,1); direction = nan(n,1);
gust = nan(n,1); wq = strings(n,1); complete = false(n,1);
seaPressure = nan(n,1); pq = strings(n,1);
if ismember('HUMIDITY_FAULT',input.Properties.VariableNames)
    humidityFault = logical(input.HUMIDITY_FAULT);
else
    humidityFault = false(n,1);
end
pole = exp(-2*pi*cfg.tempLowpassHz/cfg.fsHz);
meanN = round(cfg.windMeanSeconds*cfg.fsHz);
gustN = round(cfg.windGustSeconds*cfg.fsHz);
pressureFactor = (1-cfg.lapseRateKPerM*cfg.elevationM/cfg.seaLevelTemperatureK) ...
    ^(-cfg.gravityMPerS2*cfg.molarMassKgPerMol/ ...
    (cfg.gasConstantJPerMolK*cfg.lapseRateKPerM));
for k = 1:n
    time = input.time_s(k);
    if state.sampleCount==0, state.startTimeSeconds=time; end
    raw = input.AIR_TEMP_C(k);
    tq(k) = sampleQuality(raw,cfg.tempValidRangeC);
    if tq(k) == "GOOD"
        previousPoles=state.tempPoles;
        if ~state.tempInitialized
            % Avoid a false zero-to-ambient step at startup.
            comp(k) = raw;
            state.tempPoles(:) = raw;
            state.tempInitialized = true;
        else
            dt = time-state.tempPreviousTime;
            comp(k) = raw + cfg.tempTauSeconds/dt*(raw-state.tempPreviousRaw);
            stage = comp(k);
            for j = 1:cfg.tempLowpassPoles
                state.tempPoles(j) = pole*state.tempPoles(j)+(1-pole)*stage;
                stage = state.tempPoles(j);
            end
        end
        if any(~isfinite(state.tempPoles))
            state.tempPoles=previousPoles;
            comp(k)=NaN; tq(k)="OUT_OF_RANGE";
        else
            state.tempPreviousRaw = raw;
            state.tempPreviousTime = time;
        end
    end
    if state.tempInitialized, temp(k) = state.tempPoles(end); end
    % Derivative compensation can overshoot despite in-range raw samples.
    % Keep the diagnostic value, but never label an impossible estimate GOOD.
    if tq(k)=="GOOD" && (~isfinite(temp(k)) || ...
            temp(k)<cfg.tempValidRangeC(1) || temp(k)>cfg.tempValidRangeC(2))
        tq(k)="OUT_OF_RANGE";
    end

    raw = input.REL_HUMIDITY_PCT(k);
    hq(k) = sampleQuality(raw,[0 100]);
    if humidityFault(k), hq(k) = "DROPOUT"; end
    state.humidityIndex = mod(state.humidityIndex,cfg.humidityMedianSamples)+1;
    state.humidityCount = min(state.humidityCount+1,cfg.humidityMedianSamples);
    if hq(k) == "GOOD"
        state.humidityRaw(state.humidityIndex) = raw;
        values = state.humidityRaw(isfinite(state.humidityRaw));
        candidate = median(values);
        if ~isfinite(state.humidityAccepted)
            accept = true;
        else
            elapsed = time-state.humidityAcceptedTime;
            accept = abs(candidate-state.humidityAccepted) <= ...
                cfg.humidityMaxRatePctPerSec*elapsed + 1e-10;
        end
        if accept
            state.humidityAccepted = candidate;
            state.humidityAcceptedTime = time;
        else
            hq(k) = "SUSPECT_JUMP";
        end
    else
        % Invalid slots age out historical values even while output is held.
        state.humidityRaw(state.humidityIndex) = NaN;
    end
    rh(k) = state.humidityAccepted;

    u = input.WIND_U_MPS(k); v = input.WIND_V_MPS(k);
    state.windIndex = mod(state.windIndex,state.windCapacity)+1;
    state.windCount = min(state.windCount+1,state.windCapacity);
    if isfinite(u) && isfinite(v) && isfinite(hypot(u,v))
        speed(k) = hypot(u,v);
        state.windU(state.windIndex) = u;
        state.windV(state.windIndex) = v;
        state.windScalarSpeed(state.windIndex) = speed(k);
    else
        state.windU(state.windIndex) = NaN;
        state.windV(state.windIndex) = NaN;
        state.windScalarSpeed(state.windIndex) = NaN;
    end
    meanIdx = ringIndices(state.windIndex,min(state.windCount,meanN),state.windCapacity);
    good = isfinite(state.windU(meanIdx)) & isfinite(state.windV(meanIdx));
    if any(good)
        ubar = sum(state.windU(meanIdx(good))/nnz(good));
        vbar = sum(state.windV(meanIdx(good))/nnz(good));
        meanSpeed(k) = hypot(ubar,vbar);
        if meanSpeed(k) > cfg.windCalmThresholdMps
            direction(k) = mod(atan2d(ubar,vbar),360);
        end
    end
    gustIdx = ringIndices(state.windIndex,min(state.windCount,gustN),state.windCapacity);
    gustValues = state.windScalarSpeed(gustIdx);
    gustValues = gustValues(isfinite(gustValues));
    if ~isempty(gustValues), gust(k) = max(gustValues); end
    % Partial startup is disclosed separately. Missing samples within a
    % window are not silently represented as a full valid-window average.
    complete(k) = state.windCount >= meanN && all(good);
    if all(good), wq(k) = "GOOD"; else, wq(k) = "DROPOUT"; end

    raw = input.PRESSURE_HPA(k);
    pq(k) = sampleQuality(raw,cfg.pressureValidRangeHpa);
    if pq(k) == "GOOD", seaPressure(k) = raw*pressureFactor; end
    state.lastTimeSeconds = time;
    state.sampleCount = state.sampleCount+1;
end
state.config = cfg;
out.TEMP_CUTOFF_HZ = repmat(cfg.tempLowpassHz,n,1);
out.AIR_TEMP_COMP_C = comp;
out.AIR_TEMP_FILTERED_C = temp;
out.TEMP_QUALITY = tq;
out.REL_HUMIDITY_FILTERED_PCT = rh;
out.HUMIDITY_QUALITY = hq;
out.WIND_SPEED_MPS = speed;
out.WIND_MEAN_SPEED_MPS = meanSpeed;
out.WIND_MEAN_DIR_DEG = direction;
out.WIND_GUST_MPS = gust;
out.WIND_QUALITY = wq;
out.WIND_WINDOW_COMPLETE = complete;
out.SEA_LEVEL_PRESSURE_HPA = seaPressure;
out.PRESSURE_QUALITY = pq;
end

function quality = sampleQuality(value,bounds)
if ~isfinite(value)
    quality = "DROPOUT";
elseif value < bounds(1) || value > bounds(2)
    quality = "OUT_OF_RANGE";
else
    quality = "GOOD";
end
end

function idx = ringIndices(last,count,capacity)
idx = mod((last-count:last-1),capacity)+1;
end

function validateInput(input,state,cfg)
if ~istable(input)
    error('songdo:InvalidInput','Input must be a table.');
end
required = {'time_s','AIR_TEMP_C','REL_HUMIDITY_PCT', ...
    'WIND_U_MPS','WIND_V_MPS','PRESSURE_HPA'};
for k = 1:numel(required)
    key = required{k};
    if ~ismember(key,input.Properties.VariableNames)
        error('songdo:InvalidInput','Input is missing required column %s.',key);
    end
    value = input.(key);
    if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value) || size(value,2) ~= 1
        error('songdo:InvalidInput','Column %s must be a real two-dimensional numeric column.',key);
    end
end
if ~isa(input.time_s,'double')
    error('songdo:InvalidTime','time_s must be double precision; convert relative seconds explicitly.');
end
if ismember('HUMIDITY_FAULT',input.Properties.VariableNames)
    v = input.HUMIDITY_FAULT;
    if ~(islogical(v) || isnumeric(v)) || ~isreal(v) || ~ismatrix(v) || size(v,2) ~= 1 || ...
            any(~isfinite(v)) || any(v ~= 0 & v ~= 1)
        error('songdo:InvalidInput','HUMIDITY_FAULT must contain logical 0/1 values.');
    end
end
songdo.core.validateState(state,cfg);
% Changes to ring capacities or timing require an explicit reset. Cutoff,
% bounds, lapse constants, rate limit and calm threshold can tune live.
fixed = {'fsHz','tempTauSeconds','tempGain','tempLowpassPoles', ...
    'windMeanSeconds','windGustSeconds','humidityMedianSamples'};
for k = 1:numel(fixed)
    key = fixed{k};
    if ~isequal(cfg.(key),state.config.(key))
        error('songdo:ConfigChanged','Changing %s requires a reset.',key);
    end
end
time=input.time_s;
if state.sampleCount>0
    previous=state.lastTimeSeconds; origin=state.startTimeSeconds;
else
    previous=[]; origin=[];
end
songdo.core.validateTime(time,cfg.fsHz,previous,origin,state.sampleCount);
end
