function report = run_KMA_observations(csvPath,metadataPath,outputFolder,showFigure)
%RUN_KMA_OBSERVATIONS Native-cadence real-weather viewer, separate from run_S3.
% No resampling, sensor lag compensation, minute padding or network calls.
root=setup_project();
if nargin<4, showFigure=true; end
validateattributes(showFigure,{'logical'},{'scalar'});
if nargin<1 || isempty(csvPath)
    csvPath=fullfile(root,'data','observations','kma_observations.csv');
end
if nargin<2 || isempty(metadataPath)
    metadataPath=fullfile(fileparts(csvPath),'kma_provenance.json');
end
if nargin<3 || isempty(outputFolder)
    outputFolder=fullfile(root,'outputs','kma_observations');
end
[observations,metadata]=songdo.observations.readKma(csvPath,metadataPath);
report=songdo.observations.summarize(observations,metadata);
if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
% Retain normalized values and explicit UTC timestamps, not synthetic time_s.
export=removevars(observations,'OBSERVATION_TIME');
writetable(export,fullfile(outputFolder,'S3_KMA_observation_replay.csv'));
report.output_files=struct('observations',fullfile(outputFolder,'S3_KMA_observation_replay.csv'), ...
    'report',fullfile(outputFolder,'S3_KMA_observation_report.json'), ...
    'provenance',fullfile(outputFolder,'S3_KMA_source_provenance.json'));
writeJson(report.output_files.provenance,metadata);
report.plot_export_status='NOT_ATTEMPTED';
try
    visibility='off'; if showFigure, visibility='on'; end
    f=figure('Visible',visibility,'Color','w','Position',[100 50 1200 950], ...
        'Name','S3 | Real KMA observations | Native-cadence viewer','NumberTitle','off');
    if ~showFigure
        closeFigure=onCleanup(@()close(f)); %#ok<NASGU>
    end
    tiledlayout(f,5,1,'TileSpacing','compact');
    ax=nexttile; plot(ax,observations.OBSERVATION_TIME,observations.AIR_TEMP_C,'.');
    ylabel(ax,'Temperature (C)'); grid(ax,'on');
    title(ax,sprintf('KMA %s (%s): native recorded timestamps, no interpolation', ...
        metadata.station_name,metadata.station_id),'Interpreter','none');
    ax=nexttile; plot(ax,observations.OBSERVATION_TIME,observations.REL_HUMIDITY_PCT,'.');
    ylabel(ax,'RH (%)'); grid(ax,'on');
    ax=nexttile; plot(ax,observations.OBSERVATION_TIME,observations.WIND_SPEED_MPS,'.');
    ylabel(ax,'Wind speed (m/s)'); grid(ax,'on');
    ax=nexttile; plot(ax,observations.OBSERVATION_TIME,observations.WIND_FROM_DEG,'.');
    ylabel(ax,'Wind FROM (deg)'); ylim(ax,[0 360]); grid(ax,'on');
    ax=nexttile; plot(ax,observations.OBSERVATION_TIME, ...
        [observations.STATION_PRESSURE_HPA,observations.SEA_LEVEL_PRESSURE_HPA],'.');
    ylabel(ax,'Pressure (hPa)'); xlabel(ax,'Observation time (UTC)'); grid(ax,'on');
    legend(ax,{'Station pressure','Published sea-level pressure'},'Location','best');
    report.output_files.plot=fullfile(outputFolder,'S3_KMA_observations.png');
    exportgraphics(f,report.output_files.plot,'Resolution',150);
    report.plot_export_status='EXPORTED';
catch err
    report.plot_export_status=['UNAVAILABLE: ' err.message];
end
writeJson(report.output_files.report,report);
fprintf('Replayed %d real observation rows for %s (%s); no rows interpolated.\n', ...
    report.row_count,report.station_name,report.station_id);
fprintf('Observed row intervals (seconds): %s\n',mat2str(report.intervals_seconds));
fprintf('Pressure benchmark: %s\n',report.pressure_benchmark.status);
fprintf('10 Hz simulation and controlled plunge remain separate: run_S3.\n');
end

function writeJson(path,value)
fid=fopen(path,'w');
if fid<0, error('songdo:ObservationExport','Cannot write %s.',path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true,'ConvertInfAndNaN',true));
end
