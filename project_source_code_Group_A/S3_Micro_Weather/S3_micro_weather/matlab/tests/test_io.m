function test_io()
%TEST_IO Local schema, aggregation, replay and registry assertions.
cfg=songdo.core.defaultConfig();
meta=songdo.core.get_project_config();
assert(numel(meta.stations)==5);
assert(sum(arrayfun(@(s)numel(s.channels),meta.stations))==20);
assert(numel(unique(string({meta.stations.station_id})))==5);
input=songdo.io.generateScenario(cfg,'mixed',180);
[out,~]=songdo.core.processBlock(input,songdo.core.initState(cfg),cfg);
[grid,kma]=songdo.io.minuteTelemetry(input,out,cfg);
assert(isempty(songdo.io.validateTelemetry(grid)));
assert(numel(grid.records)==12 && numel(kma.records)==3);
assert(~any(strcmp({grid.records.channel},'SEA_LEVEL_PRESSURE_HPA')));
assert(all([kma.records.sample_count]==600));
assert(all([kma.records.sea_level_pressure_hpa]>[kma.records.station_pressure_hpa]));
assert(kma.records(1).humidity_good_count<600);
[one,~]=songdo.io.minuteTelemetry(input(1:600,:),out(1:600,:),cfg);
assert(numel(one.records)==4);
try
    songdo.io.minuteTelemetry(input(2:600,:),out(2:600,:),cfg);
    error('test:ExpectedFailure','Partial minute unexpectedly exported.');
catch err, assert(strcmp(err.identifier,'songdo:NoCompleteMinute')); end
broken=grid; broken.records(1).unit='wrong';
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=grid; broken.records(1).filtered_value=NaN; broken.records(1).quality_flag='GOOD';
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=grid; broken.records(1)=[];
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=grid; broken.extra=true;
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=grid; broken.records(1).extra=true;
assert(~isempty(songdo.io.validateTelemetry(broken)));
broken=grid; broken.records(end+1)=broken.records(1);
assert(~isempty(songdo.io.validateTelemetry(broken)));
% Direction near the 359/1 seam must average near north, not south.
x=input(1:600,:); x.WIND_U_MPS(:)=sind(359); x.WIND_U_MPS(301:end)=sind(1);
x.WIND_V_MPS(:)=cosd(1);
[o,~]=songdo.core.processBlock(x,songdo.core.initState(cfg),cfg);
[~,m]=songdo.io.minuteTelemetry(x,o,cfg);
assert(min(abs(m.records.wd_deg),abs(m.records.wd_deg-360))<1e-10);
calmCfg=cfg; calmCfg.windCalmThresholdMps=1; % Exactly representable equality case.
x.WIND_U_MPS(:)=0; x.WIND_V_MPS(:)=1;
[o,~]=songdo.core.processBlock(x,songdo.core.initState(calmCfg),calmCfg);
[g,m]=songdo.io.minuteTelemetry(x,o,calmCfg);
assert(isnan(m.records.wd_deg));
assert(strcmp(g.records(4).quality_flag,'DROPOUT'));
assert(isempty(songdo.io.validateTelemetry(g)));
assert(isempty(songdo.io.validateTelemetry(jsondecode(jsonencode(g,'ConvertInfAndNaN',true)))));
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
nullFile=fullfile(folder,'calm.json');
songdo.io.export_sensor_grid_json(jsondecode(jsonencode(g,'ConvertInfAndNaN',true)),nullFile);
nullText=fileread(nullFile); assert(contains(nullText,'null'));
file=fullfile(folder,'replay.csv'); writetable(input,file);
replay=songdo.io.readReplay(file,cfg);
a=input{:,1:6}; b=replay{:,1:6};
assert(isequal(isnan(a),isnan(b)));
d=abs(a-b); assert(all(d(isfinite(d))<1e-8));
paths=songdo.io.exportTelemetry(input,out,cfg,folder);
decoded=jsondecode(fileread(paths.sensor_grid));
assert(numel(decoded.records)==12);
fprintf('PASS test_io: registry, minutes, directions, schema and CSV replay.\n');
end
