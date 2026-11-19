function out = sitePlacement(action, M)
%SITEPLACEMENT  Load / save user-placed site overlays (map "Place site").
%   M = songdoui.sitePlacement('load')   containers.Map code -> struct(lat, lon, headingDeg)
%   songdoui.sitePlacement('save', M)    writes Integrated_UI/site_placement.json
%   f = songdoui.sitePlacement('file')   path of that file
%
%   The handbook station points (registry.m) are never changed: they are the
%   coordinates the members' JSON exports carry. A placement only moves the
%   site overlay (e.g. the S1 250 m^2 counting area) to where the team says
%   the sensor footprint actually is.
file = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'site_placement.json');
switch action
    case 'file'
        out = file;
    case 'load'
        out = containers.Map();
        if ~isfile(file), return; end
        try
            d = jsondecode(fileread(file));
        catch
            warning('songdoui:placement', 'Could not read %s; using station points.', file);
            return
        end
        for f = fieldnames(d).'
            v = d.(f{1});
            if isstruct(v) && all(isfield(v, {'lat', 'lon'}))
                if ~isfield(v, 'headingDeg') || isempty(v.headingDeg), v.headingDeg = NaN; end
                out(f{1}) = struct('lat', double(v.lat), 'lon', double(v.lon), 'headingDeg', double(v.headingDeg));
            end
        end
    case 'save'
        S = struct();
        for k = M.keys
            v = M(k{1});
            S.(k{1}) = struct('lat', v.lat, 'lon', v.lon, 'headingDeg', v.headingDeg, ...
                'note', 'site overlay position set with "Place site" in the integrated UI (handbook station point unchanged)');
        end
        fid = fopen(file, 'w');
        if fid < 0, error('songdoui:placement', 'Cannot write %s', file); end
        fwrite(fid, jsonencode(S, 'PrettyPrint', true), 'char');
        fclose(fid);
        out = file;
end
end
