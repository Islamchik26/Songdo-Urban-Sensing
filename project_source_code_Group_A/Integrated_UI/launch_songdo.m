function app = launch_songdo()
%LAUNCH_SONGDO  Open the Team A integrated Songdo Urban Sensing instrument.
%
%   >> cd Integrated_UI
%   >> launch_songdo
%
%   Adds every member folder to the path (nothing is copied or modified)
%   and opens SongdoIntegratedApp. Works from any current folder.
here = fileparts(mfilename('fullpath'));
addpath(here);
app = SongdoIntegratedApp();
if nargout == 0, clear app; end
end
