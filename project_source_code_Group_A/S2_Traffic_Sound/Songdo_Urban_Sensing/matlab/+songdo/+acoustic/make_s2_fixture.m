function fx = make_s2_fixture(varargin)
%MAKE_S2_FIXTURE  Deterministic 48 kHz / 24-bit Technopark acoustic fixture.
%
%   fx = songdo.acoustic.make_s2_fixture()
%   fx = songdo.acoustic.make_s2_fixture('Duration', 24, 'Seed', 42, 'SavePath', 'S2.mat')
%
%   Contents (everything is calibrated by A-weighted level, band-limited to
%   what the 8 kHz chain can see):
%     * traffic background       61 dBA, low-pass shaped noise, whole record
%     * diesel bus acceleration  66 dBA active, 4-9 s, 30->80 Hz engine
%                                fundamental with 27 harmonics (hard negative
%                                for the siren detector)
%     * siren wail  12-17 s, 0.25 Hz modulation, 650-950 Hz sweep  } 69 dBA
%     * siren yelp  19-22 s, 2.0 Hz modulation, 650-950 Hz sweep   } active
%     * 60 Hz mains hum (4 mV rms) and 18 kHz inverter tone (3 mV rms)
%   Mic sensitivity 20 mV/Pa, 24-bit ADC over +-1 V.
%
%   The overall level of the default record is about 66-67 dBA, inside the
%   65-68 dBA daytime band the Handbook quotes for Technopark.
%   This is a synthetic fixture built to that level, not measured data.
%
%   Output struct fx: Fs, Duration, t, volts, pClean (Pa, before hum/inverter
%   and before quantisation), Sensitivity, ADC, Events, Station, Interferers,
%   Seed.

ip = inputParser;
addParameter(ip, 'Duration', 24, @(v) isnumeric(v) && isscalar(v) && v > 0);
addParameter(ip, 'Seed', 42, @(v) isnumeric(v) && isscalar(v));
addParameter(ip, 'SavePath', '', @(v) ischar(v) || isstringscalar(v));
parse(ip, varargin{:});
dur  = ip.Results.Duration;
seed = ip.Results.Seed;

Fs   = 48000;
sens = 0.020;                      % V/Pa
Vfs  = 2.0;                        % +-1 V
nbit = 24;
N    = round(dur * Fs);
t    = (0:N-1).' / Fs;

prevRng = rng;
restore = onCleanup(@() rng(prevRng));
rng(seed, 'twister');

events = struct( ...
    'Name',  {'bus_rumble', 'siren_wail', 'siren_yelp'}, ...
    'Type',  {'rumble',     'siren',      'siren'}, ...
    'Start', {4,            12,           19}, ...
    'Stop',  {9,            17,           22});

% --- traffic background -------------------------------------------------
w     = randn(N, 1);
bgRaw = filter(1, [1 -0.9], filter(1, [1 -0.9], w));
bgRaw = bgRaw - mean(bgRaw);
bg    = scaleToDbA(bgRaw, 61.0, true(N, 1), Fs);

% --- diesel bus acceleration -------------------------------------------
a = events(1).Start;
b = events(1).Stop;
f0 = 30 + 50 * min(max((t - a)/(b - a), 0), 1);
ph = 2*pi*cumsum(f0) / Fs;
busRaw = zeros(N, 1);
for k = 1:27
    busRaw = busRaw + sin(k*ph + 2*pi*rand) / k;
end
busRaw = busRaw .* smoothEnv(t, a, b, 0.8);
bus    = scaleToDbA(busRaw, 66.0, t >= a & t < b, Fs);

% --- emergency sirens ---------------------------------------------------
sirenRaw  = sirenTone(t, events(2).Start, events(2).Stop, 0.25, Fs) ...
          + sirenTone(t, events(3).Start, events(3).Stop, 2.00, Fs);
sirenMask = (t >= events(2).Start & t < events(2).Stop) ...
          | (t >= events(3).Start & t < events(3).Stop);
siren     = scaleToDbA(sirenRaw, 69.0, sirenMask, Fs);

pClean = bg + bus + siren;

% --- electrical interferers, mic, ADC -----------------------------------
hum = 0.004 * sqrt(2) * sin(2*pi*60*t);
invTone = 0.003 * sqrt(2) * sin(2*pi*18000*t + 0.3);

volts = sens*pClean + hum + invTone;
q     = Vfs / 2^nbit;
volts = q * round(volts / q);

fx = struct();
fx.Fs          = Fs;
fx.Duration    = dur;
fx.t           = t;
fx.volts       = volts;
fx.pClean      = pClean;
fx.Sensitivity = sens;
fx.ADC         = struct('Bits', nbit, 'FullScaleV', Vfs, 'LsbV', q);
fx.Events      = events;
fx.Station     = struct('Id', 'STATION_TECHNOPARK_ACOUSTIC', ...
                        'Latitude', 37.3820, 'Longitude', 126.6560, 'ElevationM', 9.0);
fx.Interferers = struct('HumHz', 60, 'HumVrms', 0.004, ...
                        'InverterHz', 18000, 'InverterVrms', 0.003);
fx.Seed        = seed;

if strlength(string(ip.Results.SavePath)) > 0
    save(char(ip.Results.SavePath), 'fx', '-v7');
end
end

% ========================================================================
function e = smoothEnv(t, a, b, tr)
%SMOOTHENV  Linear fade in/out of length tr inside [a, b].
e = min(max((t - a)/tr, 0), 1) .* min(max((b - t)/tr, 0), 1);
end

function s = sirenTone(t, a, b, fm, Fs)
%SIRENTONE  Frequency-swept siren, 650-950 Hz, modulation fm, with harmonics.
fi = 800 + 150*sin(2*pi*fm*(t - a));
ph = 2*pi*cumsum(fi) / Fs;
s  = (sin(ph) + 0.3*sin(2*ph) + 0.15*sin(3*ph)) .* smoothEnv(t, a, b, 0.2);
end

function y = scaleToDbA(x, targetDbA, mask, Fs)
%SCALETODBA  Scale x so its A-weighted level over mask equals targetDbA.
if ~any(mask)
    y = zeros(size(x));
    return
end
cur = songdo.acoustic.reference_level_dba(x, Fs, mask);
y   = x * 10^((targetDbA - cur) / 20);
end
