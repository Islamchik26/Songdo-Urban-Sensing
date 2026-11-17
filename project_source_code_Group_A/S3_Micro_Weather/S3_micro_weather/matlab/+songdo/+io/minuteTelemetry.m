function [grid,kma] = minuteTelemetry(input,out,cfg)
%MINUTETELEMETRY Full, aligned UTC minute bins; four registered S3 channels.
% Invalid observations are excluded from numeric means and flags propagated.
% KMA-like export is explicitly a local mock, not the official KMA contract.
if height(input)~=height(out) || ~isequal(input.time_s,out.time_s)
    error('songdo:TelemetryAlignment','Input and processed observations must align.');
end
if isempty(input), error('songdo:NoCompleteMinute','No complete minute to export.'); end
base=datetime(cfg.startUtc,'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSS''Z''','TimeZone','UTC');
if isnat(base) || second(base)~=0
    error('songdo:StartUtc','cfg.startUtc must be UTC at a whole minute, e.g. 2026-01-01T00:00:00.000Z.');
end
bucket=floor((input.time_s+1e-8)/60);
ids=unique(bucket); nMinute=round(60*cfg.fsHz);
grid=struct('schema_version','1.0','generated_at',utcString(datetime('now','TimeZone','UTC')), ...
    'station_id',cfg.stationId,'latitude',cfg.latitude,'longitude',cfg.longitude,'records',[]);
record=struct('timestamp','','channel','','raw_value',NaN,'filtered_value',NaN,'unit','','quality_flag','GOOD');
records=repmat(record,0,1); km=repmat(struct(),0,1);
for id=reshape(ids,1,[])
    ix=find(bucket==id);
    expected=id*60+(0:nMinute-1)'/cfg.fsHz;
    if numel(ix)~=nMinute || any(abs(input.time_s(ix)-expected)>1e-7), continue; end
    ts=utcString(base+seconds(id*60));
    tq=worstFlag(out.TEMP_QUALITY(ix)); hq=worstFlag(out.HUMIDITY_QUALITY(ix));
    wq=worstFlag(out.WIND_QUALITY(ix)); pq=worstFlag(out.PRESSURE_QUALITY(ix));
    goodT=out.TEMP_QUALITY(ix)=="GOOD";
    goodH=out.HUMIDITY_QUALITY(ix)=="GOOD";
    % Vector mean over the minute, never an arithmetic mean of directions.
    validW=isfinite(double(input.WIND_U_MPS(ix))) & isfinite(double(input.WIND_V_MPS(ix))) & ...
        isfinite(hypot(double(input.WIND_U_MPS(ix)),double(input.WIND_V_MPS(ix))));
    meanU=safeMean(input.WIND_U_MPS(ix(validW)));
    meanV=safeMean(input.WIND_V_MPS(ix(validW)));
    vectorSpeed=hypot(meanU,meanV);
    if vectorSpeed<=cfg.windCalmThresholdMps || ~isfinite(vectorSpeed)
        vectorDir=NaN; dirFlag='DROPOUT';
    else
        vectorDir=mod(atan2d(meanU,meanV),360); dirFlag=wq;
    end
    validTRaw=isfinite(input.AIR_TEMP_C(ix)) & input.AIR_TEMP_C(ix)>=cfg.tempValidRangeC(1) & input.AIR_TEMP_C(ix)<=cfg.tempValidRangeC(2);
    validHRaw=isfinite(input.REL_HUMIDITY_PCT(ix)) & input.REL_HUMIDITY_PCT(ix)>=0 & input.REL_HUMIDITY_PCT(ix)<=100;
    if ismember('HUMIDITY_FAULT',input.Properties.VariableNames), validHRaw=validHRaw & ~input.HUMIDITY_FAULT(ix); end
    raw=[safeMean(input.AIR_TEMP_C(ix(validTRaw))),safeMean(input.REL_HUMIDITY_PCT(ix(validHRaw))), ...
        safeMean(out.WIND_SPEED_MPS(ix(validW))),vectorDir];
    filtered=[safeMean(out.AIR_TEMP_FILTERED_C(ix(goodT))),safeMean(out.REL_HUMIDITY_FILTERED_PCT(ix(goodH))),vectorSpeed,vectorDir];
    names={'AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_SPEED_MPS','WIND_DIR_DEG'};
    units={'degC','%','m/s','deg'}; flags={tq,hq,wq,dirFlag};
    for c=1:4
        q=flags{c};
        if (~isfinite(raw(c)) || ~isfinite(filtered(c))) && strcmp(q,'GOOD'), q='DROPOUT'; end
        records(end+1,1)=struct('timestamp',ts,'channel',names{c},'raw_value',raw(c), ...
            'filtered_value',filtered(c),'unit',units{c},'quality_flag',q); %#ok<AGROW>
    end
    goodP=out.PRESSURE_QUALITY(ix)=="GOOD";
    pressure=safeMean(input.PRESSURE_HPA(ix(goodP)));
    sea=safeMean(out.SEA_LEVEL_PRESSURE_HPA(ix(goodP)));
    row=struct('timestamp',ts,'ta_c',filtered(1),'rh_pct',filtered(2), ...
        'ws_mps',vectorSpeed,'wd_deg',vectorDir,'gust3s_mps',safeMax(out.WIND_GUST_MPS(ix)), ...
        'station_pressure_hpa',pressure,'sea_level_pressure_hpa',sea, ...
        'sample_count',numel(ix),'temperature_good_count',sum(goodT), ...
        'humidity_good_count',sum(goodH),'wind_valid_count',sum(validW),'pressure_good_count',sum(goodP), ...
        'temperature_quality',tq,'humidity_quality',hq,'wind_quality',wq,'pressure_quality',pq);
    if isempty(km), km=row; else, km(end+1,1)=row; end %#ok<AGROW>
end
if isempty(records), error('songdo:NoCompleteMinute','No full UTC-aligned 600-sample minute is available.'); end
grid.records=records;
provenance='UNSPECIFIED_LOCAL_DATA';
if isstruct(input.Properties.UserData) && isfield(input.Properties.UserData,'provenance')
    provenance=input.Properties.UserData.provenance;
end
kma=struct('schema_version','s3-kma-mock-1.0','schema_notice', ...
    'Project-defined KMA-style mock only; no official ASOS conformance or observed station identity asserted.', ...
    'source_type',provenance,'generated_at',grid.generated_at,'station_id',cfg.stationId, ...
    'records',km);
end
function x=safeMean(x)
x=songdo.dsp.finiteMean(x);
end
function x=safeMax(x)
x=x(isfinite(x)); if isempty(x), x=NaN; else, x=max(x); end
end
function q=worstFlag(flags)
q='GOOD'; levels=["GOOD","SUSPECT_JUMP","DROPOUT","OUT_OF_RANGE"];
for i=1:numel(levels), if any(flags==levels(i)), q=char(levels(i)); end, end
end
function s=utcString(t)
t.Format='yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''; s=char(t);
end
