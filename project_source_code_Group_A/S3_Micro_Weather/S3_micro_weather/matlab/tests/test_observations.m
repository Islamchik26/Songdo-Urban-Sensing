function test_observations()
%TEST_OBSERVATIONS Synthetic adapter-contract fixtures, NOT real observations.
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
csvPath=fullfile(folder,'test.csv'); metaPath=fullfile(folder,'test.json');
meta=struct('station_id','112','station_name','Synthetic adapter test', ...
    'source_url','https://example.invalid/test-only','timezone','UTC', ...
    'data_kind','official_observations'); % Label used only to exercise contract.
fid=fopen(metaPath,'w'); fprintf(fid,'%s',jsonencode(meta)); fclose(fid);
t=table(["2026-10-20T00:00:00Z";"2026-10-20T01:00:00Z";"2026-10-20T03:00:00Z"], ...
    repmat("112",3,1),[10;NaN;12],[60;61;62],[1;2;0],[350;10;NaN], ...
    nan(3,1),[1010;1011;1012],'VariableNames', ...
    {'TIMESTAMP_UTC','STATION_ID','AIR_TEMP_C','REL_HUMIDITY_PCT', ...
    'WIND_SPEED_MPS','WIND_FROM_DEG','STATION_PRESSURE_HPA','SEA_LEVEL_PRESSURE_HPA'});
writetable(t,csvPath);
[o,m]=songdo.observations.readKma(csvPath,metaPath);
r=songdo.observations.summarize(o,m);
assert(height(o)==3 && isnan(o.AIR_TEMP_C(2)));
assert(isequal(r.intervals_seconds,[3600 7200]) && ~r.regular_cadence);
assert(r.interpolated_rows==0 && ~r.applied_10Hz_DSP);
assert(r.missing_counts.AIR_TEMP_C==1);
assert(strcmp(r.pressure_benchmark.status,'NOT_AVAILABLE'));
% A single row does not establish a sampling cadence.
s=songdo.observations.summarize(o(1,:),m);
assert(isempty(s.intervals_seconds) && isnan(s.median_interval_seconds));
% No elevation fallback, including when paired pressure becomes available.
o.STATION_PRESSURE_HPA(:)=1000;
s=songdo.observations.summarize(o,m);
assert(strcmp(s.pressure_benchmark.status,'NOT_AVAILABLE'));
m.pressure_elevation_m=0; m.pressure_elevation_source_url='https://example.invalid/test-only';
s=songdo.observations.summarize(o,m);
assert(s.pressure_benchmark.paired_count==3);
assert(abs(s.pressure_benchmark.mean_bias_hpa+11)<1e-12);
assert(abs(s.pressure_benchmark.mae_hpa-11)<1e-12);
m.pressure_elevation_source_url=42;
s=songdo.observations.summarize(o,m);
assert(strcmp(s.pressure_benchmark.status,'NOT_AVAILABLE'));
m.pressure_elevation_source_url=["a";"b"];
s=songdo.observations.summarize(o,m);
assert(strcmp(s.pressure_benchmark.status,'NOT_AVAILABLE'));
% Duplicates, time reversal, mixed stations and missing timezone must fail.
b=t; b.TIMESTAMP_UTC(2)=b.TIMESTAMP_UTC(1); writetable(b,csvPath);
expectFailure(@()songdo.observations.readKma(csvPath,metaPath),'songdo:ObservationTime');
b=t([2 1 3],:); writetable(b,csvPath);
expectFailure(@()songdo.observations.readKma(csvPath,metaPath),'songdo:ObservationTime');
b=t; b.STATION_ID(2)="512"; writetable(b,csvPath);
expectFailure(@()songdo.observations.readKma(csvPath,metaPath),'songdo:ObservationStation');
b=t; b.TIMESTAMP_UTC(1)="2026-10-20T00:00:00"; writetable(b,csvPath);
expectFailure(@()songdo.observations.readKma(csvPath,metaPath),'songdo:ObservationTime');
writetable(t,csvPath); meta.timezone='Asia/Seoul';
fid=fopen(metaPath,'w'); fprintf(fid,'%s',jsonencode(meta)); fclose(fid);
expectFailure(@()songdo.observations.readKma(csvPath,metaPath),'songdo:ObservationMetadata');
% Verify the actual packaged default station as well as synthetic contracts.
projectRoot=fileparts(fileparts(fileparts(mfilename('fullpath'))));
[realRows,realMeta]=songdo.observations.readKma( ...
    fullfile(projectRoot,'data','observations','kma_observations.csv'), ...
    fullfile(projectRoot,'data','observations','kma_provenance.json'));
assert(strcmp(realMeta.station_id,'512') && height(realRows)==361);
assert(all(realRows.STATION_ID=="512"));
assert(all(seconds(diff(realRows.OBSERVATION_TIME))==60));
assert(all(isnan(realRows.STATION_PRESSURE_HPA)));
assert(sum(isnan(realRows.WIND_FROM_DEG))==107);
testMonthlyPressure();
fprintf('PASS test_observations: native timestamps, gaps, missing values, station identity and pressure gates.\n');
end

function expectFailure(action,identifier)
try
    action(); error('test:ExpectedFailure','Expected adapter rejection.');
catch err
    assert(strcmp(err.identifier,identifier),'Expected %s, got %s.',identifier,err.identifier);
end
end

function testMonthlyPressure()
% Explicit synthetic contract input; no network or invented source evidence.
s=struct('station_id','TEST','station_name','Synthetic monthly test', ...
    'month','2025-10','aggregation','monthly_mean','source_url','https://example.invalid/test', ...
    'pressure_elevation_source_url','https://example.invalid/test', ...
    'pressure_elevation_temporal_status','Synthetic test only', ...
    'station_pressure_hpa',1000,'sea_level_pressure_hpa',1001,'pressure_elevation_m',0);
r=songdo.observations.monthlyPressureComparison(s);
assert(r.estimated_sea_level_pressure_mean_hpa==1000 && r.signed_difference_hpa==-1);
assert(r.absolute_difference_hpa==1 && ~r.exact_station_512_requirement_satisfied);
s.pressure_elevation_m=70.2; s.station_pressure_hpa=1011.8; s.sea_level_pressure_hpa=1020;
r=songdo.observations.monthlyPressureComparison(s);
expected=1011.8*(1-0.0065*70.2/288.15)^(-9.80665*0.0289644/(8.3144598*0.0065));
assert(abs(r.estimated_sea_level_pressure_mean_hpa-expected)<1e-10);
s.month='2025-13';
expectFailure(@()songdo.observations.monthlyPressureComparison(s),'songdo:MonthlyInterval');
s.month='2025-10'; s.station_pressure_hpa=NaN;
expectFailure(@()songdo.observations.monthlyPressureComparison(s),'songdo:MonthlyValue');
end
