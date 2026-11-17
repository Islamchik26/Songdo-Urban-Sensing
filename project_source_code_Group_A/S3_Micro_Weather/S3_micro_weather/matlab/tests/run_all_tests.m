function results = run_all_tests()
%RUN_ALL_TESTS Execute S3 DSP and schema tests. Requires actual MATLAB.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root); setup_project();
tests={@test_dsp,@test_io,@test_adversarial,@test_golden,@test_observations};
names={'test_dsp','test_io','test_adversarial','test_golden','test_observations'};
results=struct('name',names,'passed',false,'message','');
for k=1:numel(tests)
    try
        tests{k}(); results(k).passed=true; results(k).message='PASS';
    catch err
        results(k).message=err.getReport('extended','hyperlinks','off');
        fprintf(2,'FAIL %s\n%s\n',names{k},results(k).message);
    end
end
assert(all([results.passed]),'songdo:TestsFailed','One or more S3 test groups failed.');
fprintf('All %d MATLAB test groups passed. This does not implement other teams.\n',numel(tests));
end
