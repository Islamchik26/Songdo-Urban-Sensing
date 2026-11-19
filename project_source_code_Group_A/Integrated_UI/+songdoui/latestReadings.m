function L = latestReadings(st)
%LATESTREADINGS  Latest value of every channel in a station's telemetry JSON.
%   L = songdoui.latestReadings(station) reads the member's exported
%   Sensor Grid JSON and returns
%     L.ok        true if the export exists and could be read
%     L.time      timestamp of the newest record
%     L.lines     {'CHANNEL  value unit  [FLAG]', ...} one per channel
%     L.headline  short text for the map label (handbook-relevant channel)
%     L.color     marker colour for the map "latest readings" view
%     L.legend    what the colour means
%     L.value     containers.Map channel -> latest numeric value
%     L.flag      containers.Map channel -> latest quality flag
%     L.grade     CAI grade string (S4) or ''
%   Nothing is recomputed: values are read from the member's own export.

good = [0.25 0.75 0.35]; warn = [1.00 0.65 0.15]; bad = [0.90 0.25 0.25]; none = [0.55 0.55 0.60];
L = struct('ok', false, 'time', '', 'lines', {{}}, 'headline', 'no telemetry export yet', ...
    'color', none, 'legend', 'grey = not exported yet', ...
    'value', containers.Map(), 'flag', containers.Map(), 'grade', '');
if ~isfile(st.jsonFile), return; end
try
    d = jsondecode(fileread(st.jsonFile));
catch
    L.headline = 'export unreadable'; L.color = bad; return
end
recs = d.records;
if isstruct(recs), recs = num2cell(recs); end
last = containers.Map();
order = {};
for k = 1:numel(recs)
    r = recs{k};
    if ~isfield(r, 'channel'), continue; end
    if ~last.isKey(r.channel), order{end+1} = r.channel; end %#ok<AGROW>
    last(r.channel) = r;
end
if isempty(order), L.headline = 'no records'; return; end
L.ok = true;
L.lines = cell(1, numel(order));
for k = 1:numel(order)
    r = last(order{k});
    L.lines{k} = sprintf('%-18s %s %s  [%s]', order{k}, num(value(r)), field(r, 'unit'), field(r, 'quality_flag'));
    L.value(order{k}) = value(r);
    L.flag(order{k}) = field(r, 'quality_flag');
    if isfield(r, 'cai_grade'), L.grade = field(r, 'cai_grade'); end
end
newest = last(order{end});
L.time = field(newest, 'timestamp');

% handbook-relevant headline + colour per station
flagColor = @(r) pick(strcmp(field(r, 'quality_flag'), 'GOOD'), good, warn);
switch st.code
    case 'S1'
        r = get1(last, 'PED_PIR_COUNT', order);
        L.headline = sprintf('Net pedestrian count %s', num(value(r)));
        L.color = flagColor(r); L.legend = 'green = GOOD quality flag, amber = flagged';
    case 'S2'
        r = get1(last, 'LEQ_1S_DBA', order); v = value(r);
        L.headline = sprintf('Leq,1s %s dBA', num(v));
        if v <= 68, L.color = good; elseif v <= 75, L.color = warn; else, L.color = bad; end
        if last.isKey('EVENT_SIREN_FLAG') && value(last('EVENT_SIREN_FLAG')) > 0
            L.headline = [L.headline '  SIREN']; L.color = bad;
        end
        L.legend = 'green <= 68 dBA (NoiseLab daytime), amber <= 75, red above or siren';
    case 'S3'
        r = get1(last, 'AIR_TEMP_C', order);
        L.headline = sprintf('Air %s degC', num(value(r)));
        if last.isKey('WIND_SPEED_MPS'), L.headline = sprintf('%s, wind %s m/s', L.headline, num(value(last('WIND_SPEED_MPS')))); end
        bads = cellfun(@(c) ~strcmp(field(last(c), 'quality_flag'), 'GOOD'), order);
        L.color = pick(any(bads), warn, good);
        L.legend = 'green = all channels GOOD, amber = a channel is flagged';
    case 'S4'
        r = get1(last, 'AQI_CAI_LEVEL', order); v = value(r);
        grade = field(r, 'cai_grade');
        L.headline = sprintf('CAI %s (%s)', num(v), grade);
        if last.isKey('PM25_UG_M3'), L.headline = sprintf('%s, PM2.5 %s', L.headline, num(value(last('PM25_UG_M3')))); end
        if v <= 50, L.color = [0.20 0.50 1.00]; elseif v <= 100, L.color = good;
        elseif v <= 250, L.color = warn; else, L.color = bad; end
        L.legend = 'Korean CAI colours: blue Good, green Moderate, orange Unhealthy, red Very Unhealthy';
    case 'S5'
        r = get1(last, 'WATER_LEVEL_M', order);
        L.headline = sprintf('Water level %s m', num(value(r)));
        L.color = flagColor(r); L.legend = 'green = GOOD quality flag, amber = flagged';
    otherwise
        r = last(order{1});
        L.headline = sprintf('%s %s', order{1}, num(value(r)));
        L.color = flagColor(r);
end
end

% -------------------------------------------------------------------------
function r = get1(last, ch, order)
if last.isKey(ch), r = last(ch); else, r = last(order{1}); end
end

function v = value(r)
v = NaN;
if isfield(r, 'filtered_value') && isnumeric(r.filtered_value) && ~isempty(r.filtered_value)
    v = double(r.filtered_value);
elseif isfield(r, 'raw_value') && isnumeric(r.raw_value) && ~isempty(r.raw_value)
    v = double(r.raw_value);
end
end

function s = field(r, name)
s = '';
if isfield(r, name) && ~isempty(r.(name)), s = char(string(r.(name))); end
end

function s = num(v)
if isnan(v), s = 'n/a'; else, s = char(string(round(v, 3, 'significant'))); end
end

function c = pick(tf, a, b)
if tf, c = a; else, c = b; end
end
