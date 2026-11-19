function M = channelSeries(st, channels)
%CHANNELSERIES  Time series of selected channels from a station's telemetry JSON.
%   M = songdoui.channelSeries(station, {'LEQ_1S_DBA', ...}) returns a
%   containers.Map channel -> struct('t', datetime (UTC), 'v', values,
%   'flag', quality flags). Values come from the member's own export
%   (filtered_value, falling back to raw_value). Missing channels are absent.
M = containers.Map();
if ~isfile(st.jsonFile), return; end
try
    d = jsondecode(fileread(st.jsonFile));
catch
    return
end
recs = d.records;
if isstruct(recs), recs = num2cell(recs); end
if ischar(channels), channels = {channels}; end
for c = channels(:).'
    sel = cellfun(@(r) isfield(r, 'channel') && strcmp(r.channel, c{1}), recs);
    if ~any(sel), continue; end
    R = recs(sel);
    n = numel(R);
    t = NaT(n, 1, 'TimeZone', 'UTC'); v = nan(n, 1); f = cell(n, 1);
    for k = 1:n
        t(k) = parseIso(R{k}.timestamp);
        v(k) = num(R{k});
        f{k} = '';
        if isfield(R{k}, 'quality_flag'), f{k} = char(string(R{k}.quality_flag)); end
    end
    [t, i] = sort(t);
    M(c{1}) = struct('t', t, 'v', v(i), 'flag', {f(i)});
end
end

function t = parseIso(s)
s = regexprep(char(string(s)), 'Z$', '');
fmts = {'yyyy-MM-dd''T''HH:mm:ss.SSS', 'yyyy-MM-dd''T''HH:mm:ss', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS'};
t = NaT('TimeZone', 'UTC');
for k = 1:numel(fmts)
    try
        t = datetime(s, 'InputFormat', fmts{k}, 'TimeZone', 'UTC');
        return
    catch
    end
end
end

function v = num(r)
v = NaN;
if isfield(r, 'filtered_value') && isnumeric(r.filtered_value) && ~isempty(r.filtered_value)
    v = double(r.filtered_value);
elseif isfield(r, 'raw_value') && isnumeric(r.raw_value) && ~isempty(r.raw_value)
    v = double(r.raw_value);
end
end
