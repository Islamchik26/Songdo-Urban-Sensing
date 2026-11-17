function cfg = get_project_config()
%GET_PROJECT_CONFIG Read source registry metadata, independent of runtime DSP.
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
cfg = jsondecode(fileread(fullfile(root,'config','project_config.json')));
end
