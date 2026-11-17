function [observations,metadata] = readKma(csvPath,metadataPath)
%READKMA Read normalized native-cadence observations without interpolation.
% Source verification is documented in the sidecar, not authenticated by CSV.
metadata=jsondecode(fileread(metadataPath));
if ~isstruct(metadata) || ~isscalar(metadata)
    error('songdo:ObservationMetadata','Metadata must be one JSON object.');
end
required={'station_id','station_name','source_url','timezone','data_kind'};
for k=1:numel(required)
    key=required{k};
    if ~isfield(metadata,key) || ~validText(metadata.(key))
        error('songdo:ObservationMetadata','Missing nonempty metadata text: %s.',key);
    end
end
if ~strcmp(metadata.timezone,'UTC') || ~strcmp(metadata.data_kind,'official_observations')
    error('songdo:ObservationMetadata','Expected UTC official_observations sidecar.');
end
names={'TIMESTAMP_UTC','STATION_ID','AIR_TEMP_C','REL_HUMIDITY_PCT', ...
    'WIND_SPEED_MPS','WIND_FROM_DEG','STATION_PRESSURE_HPA','SEA_LEVEL_PRESSURE_HPA'};
opts=detectImportOptions(csvPath,'VariableNamingRule','preserve');
if ~all(ismember(names,opts.VariableNames))
    error('songdo:ObservationColumns','Normalized CSV requires: %s.',strjoin(names,', '));
end
opts=setvartype(opts,names(1:2),'string');
opts=setvartype(opts,names(3:end),'double');
opts.ImportErrorRule='error'; % Malformed numeric text is not silently turned into missing data.
observations=readtable(csvPath,opts);
if height(observations)<1
    error('songdo:ObservationTime','No observation rows.');
end
stamp=observations.TIMESTAMP_UTC;
if any(ismissing(stamp)) || any(cellfun(@isempty,regexp(cellstr(stamp), ...
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$','once')))
    error('songdo:ObservationTime','Use explicit ISO UTC yyyy-MM-ddTHH:mm:ssZ timestamps.');
end
try
    time=datetime(stamp,'InputFormat','yyyy-MM-dd''T''HH:mm:ss''Z''','TimeZone','UTC');
catch
    error('songdo:ObservationTime','Invalid UTC timestamp.');
end
if any(isnat(time)) || any(seconds(diff(time))<=0)
    error('songdo:ObservationTime','Timestamps must be valid, unique and strictly increasing.');
end
if any(ismissing(observations.STATION_ID)) || ...
        any(observations.STATION_ID~=string(metadata.station_id))
    error('songdo:ObservationStation','Every row must match the sidecar station_id.');
end
for k=3:numel(names)
    if any(isinf(observations.(names{k})))
        error('songdo:ObservationValue','Infinity is not an observation; use blank for missing.');
    end
end
% Keep source values unchanged, including NaN. No holding, smoothing or filling.
observations.OBSERVATION_TIME=time;
observations.Properties.UserData=metadata;
end

function valid = validText(value)
valid=(ischar(value) && isrow(value) && ~isempty(value)) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value)>0);
end
