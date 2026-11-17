function root = setup_project()
%SETUP_PROJECT Add only this project's MATLAB entrypoints and tests to path.
matlabRoot = fileparts(mfilename('fullpath'));
root = fileparts(matlabRoot);
addpath(matlabRoot, fullfile(matlabRoot,'apps'), fullfile(matlabRoot,'tests'));
end
