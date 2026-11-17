function s1_export(result,jsonPath,csvPath)
% S1_EXPORT writes Handbook Section 5.3 Sensor Grid JSON and a CSV table.
if nargin<2||isempty(jsonPath), jsonPath=fullfile(pwd,'S1_telemetry.json'); end
if nargin<3||isempty(csvPath), csvPath=fullfile(pwd,'S1_telemetry.csv'); end
N=numel(result.time); stride=max(1,round(result.sampleRateHz)); idx=unique([1:stride:N,N]);
nowUtc=datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
records=repmat(struct('timestamp','','channel','','raw_value',0,'filtered_value',0,'unit','','quality_flag',''),numel(idx),1);
for j=1:numel(idx)
 n=idx(j); stamp=nowUtc+seconds(result.time(n)-result.time(1));
 stamp.Format="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
 records(j).timestamp=char(stamp); records(j).channel='PED_PIR_COUNT';
 records(j).raw_value=double(result.netCount(n)); records(j).filtered_value=double(result.netCount(n));
 records(j).unit='people'; records(j).quality_flag=char(result.qualityFlag(n));
end
packet=struct('schema_version','1.0','generated_at',char(nowUtc), ...
 'station_id',result.stationId,'latitude',result.latitude,'longitude',result.longitude,'records',records);
fid=fopen(jsonPath,'w'); assert(fid>=0,'Could not open JSON path.');
closer=onCleanup(@()fclose(fid)); fwrite(fid,jsonencode(packet,'PrettyPrint',true),'char'); clear closer;
T=table(string({records.timestamp})',string({records.channel})',[records.raw_value]', ...
 [records.filtered_value]',string({records.unit})',string({records.quality_flag})', ...
 'VariableNames',{'timestamp','channel','raw_value','filtered_value','unit','quality_flag'});
writetable(T,csvPath);
end
