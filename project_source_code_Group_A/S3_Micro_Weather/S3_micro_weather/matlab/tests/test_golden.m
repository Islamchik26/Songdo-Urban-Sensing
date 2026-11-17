function test_golden()
%TEST_GOLDEN Compare actual MATLAB results with independent Python vectors.
% The vectors are not MATLAB results; only executing THIS function establishes
% agreement. Tests default + live-retuned streams, all-invalid/overflow edges,
% sample quality flags, complete-minute summaries, and arbitrary block sizes.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
folder=fullfile(root,'verification','golden'); cfg=songdo.core.defaultConfig();
cases={'default','retuned','all_invalid','wind_overflow'};
for c=1:numel(cases)
    name=cases{c};
    if ismember(name,{'default','retuned'}), inputName='adversarial_input.csv';
    else, inputName=[name '_input.csv']; end
    input=songdo.io.readReplay(fullfile(folder,inputName),cfg);
    expected=readtable(fullfile(folder,['expected_' name '_samples.csv']), ...
        'VariableNamingRule','preserve','TextType','string');
    actual=stream(input,cfg,strcmp(name,'retuned'));
    assert(height(actual)==height(expected));
    for key=expected.Properties.VariableNames
        field=key{1}; a=actual.(field); e=expected.(field);
        if isnumeric(e)||islogical(e)
            near(double(a),double(e),strcmp(field,'WIND_MEAN_DIR_DEG'),[name '/' field]);
        else
            assert(isequal(string(a),string(e)),'Golden flags mismatch: %s/%s.',name,field);
        end
    end
    if ~strcmp(name,'retuned')
        batch=songdo.core.processBlock(input,songdo.core.initState(cfg),cfg);
        assert(isequaln(batch,actual),'Batch/chunk difference for %s.',name);
    end
    [grid,mock]=songdo.io.minuteTelemetry(input,actual,cfg);
    assert(isempty(songdo.io.validateTelemetry(grid)));
    oracle=jsondecode(fileread(fullfile(folder,['expected_' name '_minutes.json'])));
    assert(numel(mock.records)==numel(oracle));
    for k=1:numel(oracle)
        for key=reshape(fieldnames(oracle),1,[])
            field=key{1}; a=mock.records(k).(field); e=oracle(k).(field);
            if isnumeric(e)||islogical(e)
                if isempty(e), e=NaN; end % JSON null
                near(double(a),double(e),strcmp(field,'wd_deg'),[name '/' field]);
            else
                assert(strcmp(string(a),string(e)),'Golden minute mismatch: %s/%s.',name,field);
            end
        end
    end
end
fprintf('PASS test_golden: independent default/retuned and invalid-minute vectors agree in MATLAB.\n');
end
function out=stream(input,cfg,retune)
state=songdo.core.initState(cfg); parts={}; cursor=1; p=0;
sizes=[1 7 29 100 13 3 211];
while cursor<=height(input)
    p=p+1; last=min(height(input),cursor+sizes(mod(p-1,numel(sizes))+1)-1);
    if retune && cursor<=600, last=min(last,600); end
    if retune && cursor>=601, cfg.tempLowpassHz=.3; end
    [parts{p},state]=songdo.core.processBlock(input(cursor:last,:),state,cfg); %#ok<AGROW>
    cursor=last+1;
end
out=vertcat(parts{:});
end
function near(actual,expected,circular,label)
assert(isequal(size(actual),size(expected)),'Size mismatch: %s.',label);
assert(isequal(isnan(actual),isnan(expected)),'Missing-value mismatch: %s.',label);
assert(isequal(isinf(actual),isinf(expected)),'Infinity mismatch: %s.',label);
valid=isfinite(expected); a=actual(valid); e=expected(valid);
if circular, delta=abs(mod(a-e+180,360)-180); else, delta=abs(a-e); end
tolerance=1e-9+1e-10*abs(e);
assert(all(delta<=tolerance),'Numeric golden mismatch: %s.',label);
end
