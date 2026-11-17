function cfg = validateConfig(cfg)
%VALIDATECONFIG Check scalar DSP configuration before creating/updating state.
% Cutoff is per pole; three cascaded poles do not share that -3 dB cutoff.
if ~isstruct(cfg) || ~isscalar(cfg)
    error('songdo:InvalidConfig','Configuration must be a scalar structure.');
end
required = {'fsHz','tempTauSeconds','tempGain','tempLowpassHz', ...
    'tempLowpassPoles','windMeanSeconds','windGustSeconds', ...
    'humidityMedianSamples','humidityMaxRatePctPerSec','elevationM', ...
    'lapseRateKPerM','gravityMPerS2','molarMassKgPerMol', ...
    'gasConstantJPerMolK','seaLevelTemperatureK'};
for k = 1:numel(required)
    key = required{k};
    if ~isfield(cfg,key)
        error('songdo:InvalidConfig','Missing configuration field: %s.',key);
    end
    validateattributes(cfg.(key),{'numeric'},{'real','scalar','finite'},mfilename,key);
    cfg.(key) = double(cfg.(key));
end
positive = {'fsHz','tempTauSeconds','tempGain','tempLowpassHz', ...
    'windMeanSeconds','windGustSeconds','humidityMaxRatePctPerSec', ...
    'lapseRateKPerM','gravityMPerS2','molarMassKgPerMol', ...
    'gasConstantJPerMolK','seaLevelTemperatureK'};
for k = 1:numel(positive)
    if cfg.(positive{k}) <= 0
        error('songdo:InvalidConfig','%s must be positive.',positive{k});
    end
end
if cfg.tempGain ~= 1
    error('songdo:InvalidConfig','S3 PT100 compensation assumes tempGain = 1.');
end
if abs(cfg.fsHz-10) > 1e-12
    error('songdo:InvalidConfig','S3 wind processing requires fsHz = 10.');
end
sensorPole = exp(-1/(cfg.fsHz*cfg.tempTauSeconds));
filterPole = exp(-2*pi*cfg.tempLowpassHz/cfg.fsHz);
if sensorPole <= 0 || sensorPole >= 1 || filterPole <= 0 || filterPole >= 1
    error('songdo:InvalidConfig','Configured sensor/filter pole is numerically degenerate.');
end
if cfg.tempLowpassHz >= cfg.fsHz/2
    error('songdo:InvalidConfig','Temperature cutoff must be below Nyquist.');
end
if cfg.tempLowpassPoles ~= 3
    error('songdo:InvalidConfig','S3 compensation requires three lowpass poles.');
end
if cfg.humidityMedianSamples ~= 5
    error('songdo:InvalidConfig','S3 humidity processing requires five raw slots.');
end
for key = {'windMeanSeconds','windGustSeconds'}
    n = cfg.fsHz*cfg.(key{1});
    if ~isfinite(n) || n < 1 || n > flintmax || abs(n-round(n)) > 1e-10
        error('songdo:InvalidConfig','%s must span an integer number of samples.',key{1});
    end
end
if 1-cfg.lapseRateKPerM*cfg.elevationM/cfg.seaLevelTemperatureK <= 0
    error('songdo:InvalidConfig','Pressure correction has a nonpositive base.');
end
pressureFactor = (1-cfg.lapseRateKPerM*cfg.elevationM/cfg.seaLevelTemperatureK)^ ...
    (-cfg.gravityMPerS2*cfg.molarMassKgPerMol/(cfg.gasConstantJPerMolK*cfg.lapseRateKPerM));
if ~isfinite(pressureFactor) || pressureFactor <= 0
    error('songdo:InvalidConfig','Pressure correction factor must be finite and positive.');
end
if ~isfield(cfg,'tempValidRangeC'), cfg.tempValidRangeC = [-80 80]; end
if ~isfield(cfg,'pressureValidRangeHpa'), cfg.pressureValidRangeHpa = [300 1100]; end
if ~isfield(cfg,'windCalmThresholdMps'), cfg.windCalmThresholdMps = 1e-6; end
for key = {'tempValidRangeC','pressureValidRangeHpa'}
    v = cfg.(key{1});
    validateattributes(v,{'numeric'},{'real','finite','numel',2},mfilename,key{1});
    cfg.(key{1}) = double(v(:).');
    if v(1) >= v(2)
        error('songdo:InvalidConfig','%s must contain increasing bounds.',key{1});
    end
end
if cfg.tempValidRangeC(1) <= -273.15 || cfg.pressureValidRangeHpa(1) <= 0
    error('songdo:InvalidConfig','Configured temperature/pressure bounds are not physical.');
end
validateattributes(cfg.windCalmThresholdMps,{'numeric'}, ...
    {'real','scalar','finite','nonnegative'},mfilename,'windCalmThresholdMps');
cfg.windCalmThresholdMps = double(cfg.windCalmThresholdMps);
if ~isfinite(pressureFactor*cfg.pressureValidRangeHpa(2))
    error('songdo:InvalidConfig','Pressure factor overflows within the configured valid range.');
end
end
