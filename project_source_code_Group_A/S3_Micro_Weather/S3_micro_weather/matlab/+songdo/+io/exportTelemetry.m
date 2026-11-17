function paths = exportTelemetry(input,out,cfg,outputFolder)
%EXPORTTELEMETRY Validate and write local JSON/CSV. No transmission occurs.
if nargin<4, outputFolder=fullfile(pwd,'outputs'); end
[grid,kma]=songdo.io.minuteTelemetry(input,out,cfg);
issues=songdo.io.validateTelemetry(grid);
if ~isempty(issues), error('songdo:Schema','%s',strjoin(issues,newline)); end
if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
paths.sensor_grid=fullfile(outputFolder,'S3_sensor_grid.json');
paths.kma_mock=fullfile(outputFolder,'S3_kma_style_mock.json');
paths.csv=fullfile(outputFolder,'S3_minute_weather.csv');
paths.processed=fullfile(outputFolder,'S3_processed_samples.csv');
writeText(paths.sensor_grid,jsonencode(grid,'PrettyPrint',true,'ConvertInfAndNaN',true));
kmaJson=kma; kmaJson.records=num2cell(kma.records); % Force array even for one minute.
writeText(paths.kma_mock,jsonencode(kmaJson,'PrettyPrint',true,'ConvertInfAndNaN',true));
writetable(struct2table(kma.records),paths.csv);
writetable(out,paths.processed); % Includes per-sample cutoff provenance.
end
function writeText(path,txt)
fid=fopen(path,'w'); if fid<0, error('songdo:ExportFile','Cannot write %s.',path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',txt);
end
