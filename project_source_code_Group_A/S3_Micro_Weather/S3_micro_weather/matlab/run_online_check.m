function summary = run_online_check()
%RUN_ONLINE_CHECK User-run MATLAB validation with a downloadable error log.
% Use in MATLAB Online from a supported desktop browser, or desktop MATLAB.
% Does NOT open the GUI, start a receiver, upload files or contact any service.
root=setup_project(); stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
folder=fullfile(root,'outputs',['validation_' stamp]); mkdir(folder);
logFile=fullfile(folder,'S3_validation_log.txt');
diary(logFile); diary on;
closeLog=onCleanup(@()diary('off')); %#ok<NASGU>
summary=struct('matlab_release',version('-release'),'matlab_version',version, ...
    'tests_passed',false,'scenario_completed',false,'gui_tested',false, ...
    'real_KMA_benchmark_completed',false,'log_file',logFile,'output_folder',folder);
fprintf('S3 MATLAB validation started: %s\n',char(datetime('now')));
fprintf('Release: %s\nVersion: %s\nPlatform: %s\n',summary.matlab_release,summary.matlab_version,computer);
fprintf('Scope: S3 only. No GUI or real KMA benchmark is validated by this command.\n');
try
    % Code Analyzer is supplied by MATLAB itself. Diagnostics include style
    % suggestions, not only errors; actual test execution determines a pass.
    sources=dir(fullfile(root,'matlab','**','*.m'));
    count=0;
    for k=1:numel(sources)
        file=fullfile(sources(k).folder,sources(k).name);
        diagnostics=checkcode(file,'-id');
        if ~isempty(diagnostics)
            fprintf('\nCode Analyzer: %s\n',sources(k).name);
            for j=1:numel(diagnostics)
                fprintf('  Line %d: %s\n',diagnostics(j).line,diagnostics(j).message);
            end
        end
        count=count+numel(diagnostics);
    end
    summary.code_analyzer_files=numel(sources);
    summary.code_analyzer_diagnostics=count;
    fprintf('\nRunning MATLAB tests, including cross-language golden comparisons...\n');
    results=run_all_tests();
    summary.tests_passed=all([results.passed]);
    fprintf('\nRunning headless S3 simulation and local exports...\n');
    report=run_S3(folder);
    summary.scenario_completed=true;
    summary.temperature_delay_reduction_percent=report.delay_reduction_percent;
    summary.plot_export_status=report.plot_export_status;
    fprintf('\nPASS: numerical tests and scenario completed in this MATLAB session.\n');
    fprintf('GUI lifecycle and real KMA comparison are separate, still unverified.\n');
catch err
    summary.error_identifier=err.identifier;
    summary.error_report=getReport(err,'extended','hyperlinks','off');
    fprintf(2,'\nFAILED: %s\n%s\n',err.identifier,summary.error_report);
    fprintf('Send the full S3_validation_log.txt back for debugging.\n');
end
fid=fopen(fullfile(folder,'S3_validation_summary.json'),'w');
if fid>=0
    fprintf(fid,'%s\n',jsonencode(summary,'PrettyPrint',true)); fclose(fid);
else
    warning('songdo:LogSummary','Could not write summary JSON; the text diary remains available.');
end
fprintf('\nValidation log: %s\n',logFile);
fprintf('After this function returns, download the log and summary from the Files panel.\n');
end
