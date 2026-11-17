function input = readReplay(path,cfg)
%READREPLAY Strict local CSV adapter. Does not resample or infer provenance.
if nargin<2, cfg=songdo.core.defaultConfig(); end
input=readtable(path,'VariableNamingRule','preserve');
names={'time_s','AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_U_MPS','WIND_V_MPS','PRESSURE_HPA'};
if ~all(ismember(names,input.Properties.VariableNames))
    error('songdo:ReplayColumns','Replay requires columns: %s.',strjoin(names,', '));
end
for k=1:numel(names)
    value=input.(names{k});
    if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value) || size(value,2)~=1
        error('songdo:ReplayType','Column %s must be one numeric column.',names{k});
    end
    input.(names{k})=double(value);
end
if height(input)<1, error('songdo:ReplayTime','Replay must contain at least one sample.'); end
songdo.core.validateTime(input.time_s,cfg.fsHz,[],[],0,'songdo:ReplayTime');
if ismember('HUMIDITY_FAULT',input.Properties.VariableNames)
    f=input.HUMIDITY_FAULT;
    if ~(islogical(f)||isnumeric(f)) || any(~ismember(f,[0 1]))
        error('songdo:ReplayFault','HUMIDITY_FAULT must contain only 0 or 1.');
    end
    input.HUMIDITY_FAULT=logical(f);
else
    input.HUMIDITY_FAULT=false(height(input),1);
end
input.Properties.UserData=struct('provenance','LOCAL_CSV_REPLAY', ...
    'sourceFile',char(path),'startUtc',cfg.startUtc);
end
