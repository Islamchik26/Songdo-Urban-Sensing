function v = validateSensorGrid(src, R)
%VALIDATESENSORGRID  Handbook Section 5.3 schema check for any station.
%   v = songdoui.validateSensorGrid(jsonFileOrText, registry)
%   v.ok        true when there are no ERRORS (warnings allowed)
%   v.errors    cellstr of schema violations
%   v.warnings  cellstr of non-fatal deviations (e.g. non-standard flags)
%   v.nRecords, v.channels, v.stationId, v.summary

if nargin < 2, R = songdoui.registry(); end
v = struct('ok', false, 'errors', {{}}, 'warnings', {{}}, 'nRecords', 0, ...
    'channels', {{}}, 'stationId', '', 'summary', '', 'file', '');

try
    if isfile(src)
        v.file = src;
        txt = fileread(src);
    else
        txt = src;
    end
    pkt = jsondecode(txt);
catch err
    v.errors{end+1} = ['Not readable / not valid JSON: ' err.message];
    v.summary = v.errors{1};
    return
end

isoRe = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$';
top = {'schema_version', 'generated_at', 'station_id', 'latitude', 'longitude', 'records'};
for k = 1:numel(top)
    if ~isfield(pkt, top{k}), v.errors{end+1} = ['Missing top-level field "' top{k} '"']; end
end
if ~isempty(v.errors), v.summary = strjoin(v.errors, '; '); return; end

if ~strcmp(string(pkt.schema_version), "1.0")
    v.errors{end+1} = sprintf('schema_version is "%s", expected "1.0"', string(pkt.schema_version));
end
if isempty(regexp(char(pkt.generated_at), isoRe, 'once'))
    v.errors{end+1} = sprintf('generated_at "%s" is not ISO-8601 UTC', char(pkt.generated_at));
end
v.stationId = char(pkt.station_id);
ids = {R.stations.stationId};
hit = find(strcmp(ids, v.stationId), 1);
if isempty(hit)
    v.errors{end+1} = sprintf('Unknown station_id "%s"', v.stationId);
else
    st = R.stations(hit);
    if abs(pkt.latitude - st.lat) > 1e-3 || abs(pkt.longitude - st.lon) > 1e-3
        v.errors{end+1} = sprintf('Coordinates (%.4f, %.4f) differ from registry (%.4f, %.4f)', ...
            pkt.latitude, pkt.longitude, st.lat, st.lon);
    end
end

recs = pkt.records;
if isstruct(recs), recs = num2cell(recs); end      % heterogeneous records decode as cell
v.nRecords = numel(recs);
if v.nRecords == 0, v.errors{end+1} = 'records array is empty'; end

need = {'timestamp', 'channel', 'raw_value', 'filtered_value', 'unit', 'quality_flag'};
badTs = 0; badNum = 0; missing = 0; odd = {};
chans = cell(1, v.nRecords);
for k = 1:v.nRecords
    r = recs{k};
    if ~all(isfield(r, need)), missing = missing + 1; continue; end
    chans{k} = char(r.channel);
    if isempty(regexp(char(r.timestamp), isoRe, 'once')), badTs = badTs + 1; end
    if ~(isNumOrNull(r.raw_value) && isNumOrNull(r.filtered_value)), badNum = badNum + 1; end
    f = char(r.quality_flag);
    if ~ismember(f, R.allowedFlags), odd{end+1} = f; end %#ok<AGROW>
end
if missing, v.errors{end+1} = sprintf('%d record(s) missing required fields', missing); end
if badTs,   v.errors{end+1} = sprintf('%d record(s) with non ISO-8601 UTC timestamp', badTs); end
if badNum,  v.errors{end+1} = sprintf('%d record(s) with non-numeric raw/filtered value', badNum); end
if ~isempty(odd)
    u = unique(odd);
    v.warnings{end+1} = sprintf('Non-handbook quality flag(s) %s in %d record(s) (handbook eq. 15 allows GOOD/DROPOUT/OUT_OF_RANGE/SUSPECT_JUMP)', ...
        strjoin(u, ', '), numel(odd));
end
v.channels = unique(chans(~cellfun(@isempty, chans)));
v.ok = isempty(v.errors);
if v.ok
    v.summary = sprintf('VALID: %d records, channels %s', v.nRecords, strjoin(v.channels, ', '));
else
    v.summary = ['INVALID: ' strjoin(v.errors, '; ')];
end
if ~isempty(v.warnings), v.summary = [v.summary ' | WARNING: ' strjoin(v.warnings, '; ')]; end
end

function tf = isNumOrNull(x)
tf = isempty(x) || (isnumeric(x) && isscalar(x)) || islogical(x);
end
