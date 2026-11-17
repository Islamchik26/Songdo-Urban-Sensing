function paths = generate_fixtures(outputFolder)
%GENERATE_FIXTURES Make deterministic seed-42 MAT/CSV inputs locally.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
if nargin<1, outputFolder=fullfile(root,'data','fixtures'); end
if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
cfg=songdo.core.defaultConfig();
input=songdo.io.generateScenario(cfg,'mixed',cfg.durationSeconds);
paths.mat=fullfile(outputFolder,'S3_centralpark_weather.mat');
paths.csv=fullfile(outputFolder,'S3_centralpark_weather.csv');
save(paths.mat,'input','cfg'); writetable(input,paths.csv);
clean=songdo.io.generateScenario(cfg,'temperature_plunge',180);
paths.plunge=fullfile(outputFolder,'S3_temperature_plunge.csv');
writetable(clean,paths.plunge);
end
