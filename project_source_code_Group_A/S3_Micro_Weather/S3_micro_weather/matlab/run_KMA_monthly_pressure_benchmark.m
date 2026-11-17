function report = run_KMA_monthly_pressure_benchmark(sourcePath,outputFolder)
%RUN_KMA_MONTHLY_PRESSURE_BENCHMARK Separate monthly alternative, not AWS replay.
root=setup_project();
if nargin<1 || isempty(sourcePath)
    sourcePath=fullfile(root,'data','pressure_benchmark','kma_monthly_pressure.json');
end
if nargin<2 || isempty(outputFolder)
    outputFolder=fullfile(root,'outputs','kma_monthly_pressure');
end
source=jsondecode(fileread(sourcePath));
report=songdo.observations.monthlyPressureComparison(source);
if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
reportFile=fullfile(outputFolder,'S3_KMA_monthly_pressure_comparison.json');
fid=fopen(reportFile,'w');
if fid<0, error('songdo:MonthlyExport','Cannot write comparison report.'); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
fprintf('KMA %s (%s), %s monthly means: descriptive alternative only.\n', ...
    report.station_name,report.station_id,report.month);
fprintf('Estimated SLP %.6f hPa; published mean %.1f hPa; signed difference %.6f hPa.\n', ...
    report.estimated_sea_level_pressure_mean_hpa,report.published_sea_level_pressure_mean_hpa, ...
    report.signed_difference_hpa);
fprintf('Elevation evidence: %s. No pass/fail threshold.\n',report.pressure_elevation_temporal_status);
fprintf('This is not the exact assignment station-512 cross-check. Report: %s\n',reportFile);
end
