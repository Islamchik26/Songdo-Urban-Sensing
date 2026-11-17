function issues = validateTelemetry(grid)
%VALIDATETELEMETRY Strict local four-channel Sensor Grid contract.
issues=strings(0,1);
required={'schema_version','generated_at','station_id','latitude','longitude','records'};
if ~isstruct(grid)||~isscalar(grid)||~isequal(sort(fieldnames(grid)),sort(required(:)))
    issues(end+1)="Incorrect top-level Sensor Grid fields."; return;
end
if ~textScalar(grid.schema_version)||~strcmp(grid.schema_version,'1.0'), issues(end+1)="Unsupported schema_version."; end
if ~textScalar(grid.station_id)||~strcmp(grid.station_id,'STATION_CENTRAL_PARK_WEATHER'), issues(end+1)="Wrong S3 station."; end
if ~finiteNumber(grid.latitude)||abs(grid.latitude)>90, issues(end+1)="Invalid latitude."; end
if ~finiteNumber(grid.longitude)||abs(grid.longitude)>180, issues(end+1)="Invalid longitude."; end
if ~validTimestamp(grid.generated_at), issues(end+1)="Invalid generated_at UTC timestamp."; end
r=grid.records; fields={'timestamp','channel','raw_value','filtered_value','unit','quality_flag'};
if ~isstruct(r)||isempty(r)||~isvector(r)||~isequal(sort(fieldnames(r)),sort(fields(:)))
    issues(end+1)="Incorrect or empty records."; return;
end
channels={'AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_SPEED_MPS','WIND_DIR_DEG'}; units={'degC','%','m/s','deg'};
keys=strings(numel(r),1); stamps=strings(numel(r),1); recordChannels=strings(numel(r),1);
for k=1:numel(r)
    if textScalar(r(k).channel), c=find(strcmp(r(k).channel,channels),1); recordChannels(k)=string(r(k).channel);
    else, c=[]; end
    if isempty(c), issues(end+1)="Unknown registered S3 channel."; %#ok<AGROW>
    elseif ~textScalar(r(k).unit)||~strcmp(r(k).unit,units{c}), issues(end+1)="Channel/unit mismatch."; end %#ok<AGROW>
    if ~validTimestamp(r(k).timestamp), issues(end+1)="Invalid record UTC timestamp."; %#ok<AGROW>
    else, stamps(k)=string(r(k).timestamp); end
    flag=r(k).quality_flag;
    flagValid=textScalar(flag) && ismember(string(flag),["GOOD","DROPOUT","OUT_OF_RANGE","SUSPECT_JUMP"]);
    if ~flagValid, issues(end+1)="Invalid quality flag."; end %#ok<AGROW>
    for name={'raw_value','filtered_value'}
        value=r(k).(name{1});
        numeric=isnumeric(value)&&~issparse(value)&&isreal(value)&&isscalar(value);
        jsonNull=isnumeric(value)&&~issparse(value)&&isempty(value); % jsondecode represents null as [].
        if jsonNull
            invalid=flagValid&&strcmp(flag,'GOOD');
        else
            invalid=~numeric || isinf(value) || (isnan(value)&&flagValid&&strcmp(flag,'GOOD'));
        end
        if invalid
            issues(end+1)="Invalid numeric/null value or GOOD flag with missing value."; %#ok<AGROW>
        end
    end
    keys(k)=stamps(k)+"/"+recordChannels(k);
end
if numel(unique(keys))~=numel(keys), issues(end+1)="Duplicate minute/channel record."; end
for stamp=reshape(unique(stamps),1,[])
    found=recordChannels(stamps==stamp);
    if numel(found)~=4 || ~isequal(sort(found),sort(string(channels(:))))
        issues(end+1)="Each minute must contain exactly four registered channels."; %#ok<AGROW>
    end
end
end
function yes=finiteNumber(x)
yes=isnumeric(x)&&~issparse(x)&&isreal(x)&&isscalar(x)&&isfinite(x);
end
function yes=textScalar(s)
yes=(ischar(s)&&isrow(s))||(isstring(s)&&isscalar(s)&&~ismissing(s));
end
function yes=validTimestamp(s)
yes=textScalar(s) && ~isempty(regexp(char(s),'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$','once'));
if yes
    try
        d=datetime(s,'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSS''Z''','TimeZone','UTC'); yes=~isnat(d);
    catch, yes=false;
    end
end
end
