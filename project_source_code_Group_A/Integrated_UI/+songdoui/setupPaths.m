function R = setupPaths()
%SETUPPATHS  Put every member module on the MATLAB path (no files copied).
%   S2 (+songdo/+acoustic) and S3 (+songdo/+core,+dsp,+io,+observations)
%   both use the "songdo" namespace with different sub-packages, so MATLAB
%   merges them without conflict.
R = songdoui.registry();
addpath(R.uiRoot);
for st = R.stations
    for k = 1:numel(st.paths)
        if isfolder(st.paths{k}), addpath(st.paths{k}); end
    end
end
if ~isfolder(R.exportDir), mkdir(R.exportDir); end
end
