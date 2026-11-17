function report = run_S3(outputFolder,replayPath)
%RUN_S3 Noninteractive S3 simulation/replay, export and clean plunge evidence.
% From matlab/: setup_project; report=run_S3(); app=SongdoSensorApp();
root=setup_project(); cfg=songdo.core.defaultConfig();
if nargin<1 || isempty(outputFolder), outputFolder=fullfile(root,'outputs'); end
if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
if nargin<2 || isempty(replayPath)
    input=songdo.io.generateScenario(cfg,'mixed',cfg.durationSeconds);
else
    input=songdo.io.readReplay(replayPath,cfg);
end
out=stream(input,cfg);
paths=songdo.io.exportTelemetry(input,out,cfg,outputFolder);
clean=songdo.io.generateScenario(cfg,'temperature_plunge',180);
cleanOut=stream(clean,cfg);
% First interpolated 50% crossing after the known t=30s, 25-to-20C step.
rawDelay=crossing(clean.time_s,clean.AIR_TEMP_C,22.5,30)-30;
filteredDelay=crossing(cleanOut.time_s,cleanOut.AIR_TEMP_FILTERED_C,22.5,30)-30;
reduction=100*(1-filteredDelay/rawDelay);
report=struct('scope','S3 only','runtime','MATLAB', ...
    'source_type',input.Properties.UserData.provenance,'processed_sample_count',height(input), ...
    'temperature_delay_metric','First linearly interpolated 50% crossing after a clean 5 C plunge at t=30 s', ...
    'raw_delay_seconds',rawDelay,'compensated_delay_seconds',filteredDelay, ...
    'delay_reduction_percent',reduction,'temperature_acceptance_pass',reduction>=65, ...
    'telemetry_schema_violations',0,'real_KMA_benchmark','NOT_RUN: use run_KMA_observations separately; paired station pressure is unavailable', ...
    'output_files',paths,'plot_export_status','NOT_ATTEMPTED');
writeJson(fullfile(outputFolder,'S3_run_report.json'),report);
if ~report.temperature_acceptance_pass
    error('songdo:TemperatureAcceptance','Clean plunge delay reduction %.2f%% is below 65%%.',reduction);
end
try
    f=figure('Visible','off','Color','w','Position',[100 100 1200 850]);
    closeFigure=onCleanup(@()close(f)); %#ok<NASGU>
    tiledlayout(f,3,1,'TileSpacing','compact');
    ax=nexttile; plot(ax,clean.time_s,[clean.TRUE_AIR_TEMP_C,clean.AIR_TEMP_C,cleanOut.AIR_TEMP_FILTERED_C]);
    xlim(ax,[20 80]); grid(ax,'on'); ylabel(ax,'Temperature (C)');
    legend(ax,{'Truth','PT100 raw','Compensated + 3 poles'},'Location','best');
    title(ax,sprintf('S3 clean synthetic 5 C plunge: %.1f%% t50 delay reduction',reduction));
    ax=nexttile; plot(ax,input.time_s,[input.REL_HUMIDITY_PCT,out.REL_HUMIDITY_FILTERED_PCT]);
    grid(ax,'on'); ylabel(ax,'Humidity (%)'); legend(ax,{'Raw','Cleaned'},'Location','best');
    ax=nexttile; plot(ax,input.time_s,[out.WIND_SPEED_MPS,out.WIND_MEAN_SPEED_MPS,out.WIND_GUST_MPS]);
    grid(ax,'on'); xlabel(ax,'Time (s)'); ylabel(ax,'Wind (m/s)');
    legend(ax,{'Instant scalar','10 s vector mean','3 s peak gust'},'Location','best');
    exportgraphics(f,fullfile(outputFolder,'S3_results.png'),'Resolution',160);
    report.plot_export_status='EXPORTED';
catch err
    report.plot_export_status='FAILED';
    report.plot_export_error=err.message;
    warning('songdo:PlotUnavailable','Numeric results exported; plot unavailable: %s',err.message);
end
writeJson(fullfile(outputFolder,'S3_run_report.json'),report);
fprintf('S3: %d samples; %.2f%% t50 delay reduction; JSON validated.\n',height(input),reduction);
fprintf('Files: %s\nReal KMA benchmark is pending.\n',outputFolder);
end
function out=stream(input,cfg)
state=songdo.core.initState(cfg); parts=cell(ceil(height(input)/cfg.blockSamples),1); p=0;
for first=1:cfg.blockSamples:height(input)
    p=p+1; last=min(first+cfg.blockSamples-1,height(input));
    [parts{p},state]=songdo.core.processBlock(input(first:last,:),state,cfg);
end
out=vertcat(parts{:});
end
function t=crossing(time,value,target,start)
i=find(time>=start & value<=target,1);
if isempty(i), t=NaN; return; end
if i==1 || value(i)==value(i-1), t=time(i); return; end
t=time(i-1)+(target-value(i-1))*(time(i)-time(i-1))/(value(i)-value(i-1));
end
function writeJson(path,data)
fid=fopen(path,'w'); if fid<0, error('songdo:ExportFile','Cannot write report.'); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(data,'PrettyPrint',true));
end
