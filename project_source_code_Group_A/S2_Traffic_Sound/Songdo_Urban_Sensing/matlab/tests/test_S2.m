function ok = test_S2()
%TEST_S2  Unit and numerical tests for the Team S2 acoustic module.
%
%   cd matlab/tests
%   test_S2;            % prints PASS/FAIL per test, errors if any test fails
%   ok = test_S2;       % returns true/false instead of erroring
%
%   Base MATLAB only. Independent of the other teams' code.

thisDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisDir, '..'));

R = cell(0, 3);
p0 = 20e-6;
Fs = 48000;
FsOut = 8000;

%% 1. A-weighting accuracy and stability
[sos, g] = songdo.acoustic.design_a_weighting(FsOut);
fT  = [63 100 125 250 500 1000 2000];
Hd  = 20*log10(abs(songdo.acoustic.sos_response(sos, g, fT, FsOut)));
Ha  = songdo.acoustic.a_weight_db(fT(:));
R   = rec(R, 'A-weighting within 0.5 dB of IEC, 63 Hz-2 kHz', all(abs(Hd - Ha) <= 0.5), sprintf('max err %.2f dB', max(abs(Hd - Ha))));
R   = rec(R, 'A-weighting IEC anchors (1k=0, 100=-19.1, 2k=+1.2, 63=-26.2)', ...
          abs(Ha(6)) < 0.01 && abs(Ha(2) + 19.1) < 0.05 && abs(Ha(7) - 1.2) < 0.05 && abs(Ha(1) + 26.2) < 0.05, '');
stable = true;
for k = 1:size(sos, 1)
    stable = stable && all(abs(roots(sos(k, 4:6))) < 1);
end
R = rec(R, 'A-weighting biquads stable', stable, '');

%% 2. Anti-alias FIR: odd, symmetric, unity DC, linear phase, stopband
h = songdo.acoustic.design_fir_lowpass(101, 3600, Fs);
n = 0:numel(h)-1;
R = rec(R, 'FIR length 101, symmetric h[n]=h[N-1-n]', numel(h) == 101 && max(abs(h - fliplr(h))) == 0, '');
R = rec(R, 'FIR DC gain = 1', abs(sum(h) - 1) < 1e-12, '');
wTest = 2*pi*[200 1000 2000]/Fs;
lp = true;
for w = wTest
    Hf = sum(h .* exp(-1j*w*n));
    lp = lp && abs(imag(Hf*exp(1j*w*50))) < 1e-9*abs(Hf);      % phase = -50*w exactly
end
R = rec(R, 'FIR exact linear phase, group delay 50 samples', lp, '');
H18 = abs(sum(h .* exp(-1j*2*pi*18000/Fs*n)));
R = rec(R, 'FIR attenuates 18 kHz by >= 50 dB', 20*log10(H18) <= -50, sprintf('%.1f dB', 20*log10(H18)));
R = tryOdd(R);

%% 3. Notch
[nb, na] = songdo.acoustic.design_notch(60, 30, Fs);
z1  = @(f) exp(-1j*2*pi*f/Fs);
Hn  = @(f) (nb(1) + nb(2)*z1(f) + nb(3)*z1(f)^2) / (na(1) + na(2)*z1(f) + na(3)*z1(f)^2);
R = rec(R, 'Notch zero at 60 Hz (< -100 dB)', 20*log10(abs(Hn(60)) + eps) < -100, '');
R = rec(R, 'Notch passes 50 Hz and 1 kHz (> -1 dB)', 20*log10(abs(Hn(50))) > -1 && 20*log10(abs(Hn(1000))) > -0.01, '');
R = rec(R, 'Notch stable', all(abs(roots(na)) < 1), '');

%% 4. Streaming: block-wise == batch, and per-block reset is wrong
fx3 = songdo.acoustic.make_s2_fixture('Duration', 3);
v   = fx3.volts;
chA = songdo.acoustic.AcousticChain();
pAll = chA.process(v);

chB = songdo.acoustic.AcousticChain();
sizes = [4800 1000 777 4801 12345 1];
pos = 0; k = 0; pBlk = zeros(0, 1);
while pos < numel(v)
    k = k + 1;
    L = min(sizes(mod(k-1, numel(sizes)) + 1), numel(v) - pos);
    pBlk = [pBlk; chB.process(v(pos+1:pos+L))]; %#ok<AGROW>
    pos = pos + L;
end
R = rec(R, 'Streaming blocks == batch (state continuity)', numel(pBlk) == numel(pAll) && max(abs(pBlk - pAll)) < 1e-9, ...
        sprintf('max diff %.1e Pa', max(abs(pBlk - pAll))));

pBad = zeros(0, 1);
for i0 = 1:4800:numel(v)-4799
    c = songdo.acoustic.AcousticChain();            % fresh state every block = the classic bug
    pBad = [pBad; c.process(v(i0:i0+4799))]; %#ok<AGROW>
end
nCmp = min(numel(pBad), numel(pAll));
R = rec(R, 'Per-block state reset is detectably wrong', max(abs(pBad(1:nCmp) - pAll(1:nCmp))) > 1e-6, '');
R = rec(R, 'Decimated length = N/6', numel(pAll) == numel(v)/6, sprintf('%d', numel(pAll)));

%% 5. Aliasing demonstration
t1  = (0:Fs-1).'/Fs;
tone18 = 0.01*sin(2*pi*18000*t1);
cG  = songdo.acoustic.AcousticChain();
cN  = songdo.acoustic.AcousticChain('BypassAntiAlias', true);
[~, xg] = cG.process(tone18);
[~, xn] = cN.process(tone18);
sel = FsOut/4 + 1 : numel(xg);                      % skip start-up
aG  = songdo.acoustic.tone_amplitude(xg(sel), FsOut, 2000);
aN  = songdo.acoustic.tone_amplitude(xn(sel), FsOut, 2000);
R = rec(R, 'No anti-alias FIR: 18 kHz folds to 2 kHz at full strength', aN > 0.008, sprintf('%.2e V', aN));
R = rec(R, 'With FIR: 2 kHz alias <= 1e-4 V (>= 40 dB down)', aG <= 1e-4, sprintf('%.2e V', aG));

%% 6. Calibration: 1 Pa rms at 1 kHz = 94 dB SPL = 94 dBA
t3 = (0:3*Fs-1).'/Fs;
sens = 0.020;
tone1k = sens*sqrt(2)*sin(2*pi*1000*t3);
cC = songdo.acoustic.AcousticChain('Sensitivity', sens);
pC = cC.process(tone1k);
Lc = songdo.acoustic.level_series(pC, FsOut, 1.0, 1.0);
R = rec(R, '1 kHz, 1 Pa rms reads 94.0 dBA (+-0.1)', abs(Lc(end) - 94) < 0.1, sprintf('%.2f dBA', Lc(end)));

tone100 = sens*sqrt(2)*sin(2*pi*100*t3);
cD = songdo.acoustic.AcousticChain('Sensitivity', sens);
pD = cD.process(tone100);
Ld = songdo.acoustic.level_series(pD, FsOut, 1.0, 1.0);
Lexp = 20*log10(1/p0) + songdo.acoustic.a_weight_db(100);      % 93.98 - 19.14
R = rec(R, '100 Hz, 1 Pa rms reads IEC A-weighted level (+-0.3 dB)', abs(Ld(end) - Lexp) < 0.3, ...
        sprintf('%.2f dBA, expected %.2f', Ld(end), Lexp));

[Lw, tw] = songdo.acoustic.level_series(ones(8000, 1), 8000, 0.5, 0.1);
R = rec(R, 'level_series is causal: first value at t = window length', abs(tw(1) - 0.5) < 1e-12 && numel(Lw) == 6, '');

%% 7. Schmitt trigger
x  = [0 .2 .5 .6 .4 .3 .1 .4 .6 .2];
sE = [0  0  0  1  1  0  0  0  1  0].';
s  = songdo.acoustic.schmitt_trigger(x, 0.55, 0.35);
R = rec(R, 'Schmitt hysteresis latching', isequal(s, sE), '');
rng(1);
chat = 0.45 + 0.05*randn(1000, 1);
chat = min(max(chat, 0.36), 0.54);
R = rec(R, 'Schmitt: noise inside the dead band never toggles', all(songdo.acoustic.schmitt_trigger(chat, 0.55, 0.35) == 0), '');
[~, sf] = songdo.acoustic.schmitt_trigger([0 1 0.5], 0.55, 0.35);
R = rec(R, 'Schmitt: final state returned for streaming', sf == 1, '');

%% 8. STFT features
t8  = (0:8*FsOut-1).'/FsOut;
F1  = songdo.acoustic.stft_features(sin(2*pi*800*t8), FsOut);
F2  = songdo.acoustic.stft_features(sin(2*pi*3000*t8), FsOut);
R = rec(R, 'STFT frame count', numel(F1.Time) == floor((numel(t8) - 512)/256) + 1, '');
R = rec(R, 'STFT first frame stamped at its last sample (512/Fs)', abs(F1.Time(1) - 512/FsOut) < 1e-12, '');
R = rec(R, '800 Hz tone: siren ratio > 0.9, centroid within 20 Hz', min(F1.SirenRatio) > 0.9 && abs(median(F1.Centroid) - 800) < 20, ...
        sprintf('eta %.3f, centroid %.0f Hz', min(F1.SirenRatio), median(F1.Centroid)));
R = rec(R, '3 kHz tone: HF ratio > 0.95, siren ratio < 0.05', min(F2.HfRatio) > 0.95 && max(F2.SirenRatio) < 0.05, '');

%% 9. Amplitude spectrum normalisation
ta = (0:4*Fs-1).'/Fs;
Aa = songdo.acoustic.tone_amplitude(0.5*sin(2*pi*1000*ta), Fs, 1000);
R = rec(R, 'Hann coherent-gain correction recovers amplitude', abs(Aa - 0.5) < 0.005, sprintf('%.4f', Aa));

%% 10. Quality flags
xq = [60 61 NaN 62 200 62 100 101];
fE = ["GOOD"; "GOOD"; "DROPOUT"; "GOOD"; "OUT_OF_RANGE"; "SUSPECT_JUMP"; "SUSPECT_JUMP"; "GOOD"];
fq = songdo.acoustic.quality_flags(xq, 0.1, [30 130], 150);
R = rec(R, 'Quality flags DROPOUT / OUT_OF_RANGE / SUSPECT_JUMP / GOOD', isequal(fq, fE), '');

%% 11. End-to-end on the default fixture
fx  = songdo.acoustic.make_s2_fixture();
fx2 = songdo.acoustic.make_s2_fixture();
R = rec(R, 'Fixture is deterministic (seed 42)', isequal(fx.volts, fx2.volts), '');
R = rec(R, 'Fixture inside ADC range', max(abs(fx.volts)) < 1, sprintf('peak %.3f V', max(abs(fx.volts))));

ch  = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity);
[pF, xD] = ch.process(fx.volts);
Lchain = 10*log10(mean(pF(FsOut+1:end).^2)/p0^2);
Lref   = songdo.acoustic.reference_level_dba(fx.pClean, Fs, fx.t >= 1);
R = rec(R, 'Chain Leq within 0.5 dB of analytic truth', abs(Lchain - Lref) <= 0.5, sprintf('chain %.2f, truth %.2f dBA', Lchain, Lref));
R = rec(R, 'Fixture Leq inside NoiseLab 65-68 dBA', Lchain >= 65 && Lchain <= 68, sprintf('%.2f dBA', Lchain));

Ff   = songdo.acoustic.stft_features(xD, FsOut);
flag = songdo.acoustic.schmitt_trigger(Ff.SirenRatio, 0.55, 0.35);
iv   = [12 17; 19 22];
inIv = false(size(Ff.Time));
allDet = true;
for k = 1:2
    wIv  = Ff.Time >= iv(k,1) & Ff.Time <= iv(k,2) + 0.5;
    inIv = inIv | wIv;
    allDet = allDet && any(flag(wIv) == 1);
end
bus = Ff.Time >= 4 & Ff.Time <= 9;
R = rec(R, 'Siren detected in both events', allDet, '');
R = rec(R, 'No siren flag during diesel bus rumble', ~any(flag(bus) == 1), sprintf('max eta %.2f', max(Ff.SirenRatio(bus))));
R = rec(R, 'No siren flag outside siren events', ~any(flag(~inIv) == 1), '');

%% 12. JSON export schema
tick = (10:60).';
m = struct('Time', tick*0.1, 'MicRawRms', 0.01*ones(51,1), 'MicFiltRms', 0.01*ones(51,1), ...
           'SplZ', 65*ones(51,1), 'SplA', 62*ones(51,1), 'LeqZ', 66*ones(51,1), 'LeqA', 63*ones(51,1), ...
           'SirenRatio', 0.2*ones(51,1), 'SirenFlag', zeros(51,1));
t0 = datetime(2026, 10, 2, 12, 0, 0, 'TimeZone', 'UTC');
js = songdo.acoustic.export_s2_json(m, fx.Station, t0);
pk = jsondecode(js);
req = {'timestamp', 'channel', 'raw_value', 'filtered_value', 'unit', 'quality_flag'};
okTop = all(isfield(pk, {'schema_version', 'generated_at', 'station_id', 'latitude', 'longitude', 'records'}));
okRec = numel(pk.records) == 51*4 && all(isfield(pk.records, req));
okTs  = all(~cellfun('isempty', regexp({pk.records.timestamp}, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$', 'once')));
R = rec(R, 'JSON top-level fields + station id + coordinates', okTop && strcmp(pk.station_id, 'STATION_TECHNOPARK_ACOUSTIC') ...
        && abs(pk.latitude - 37.3820) < 1e-9 && abs(pk.longitude - 126.6560) < 1e-9, '');
R = rec(R, 'JSON records: 4 channels x N, all 6 fields', okRec, '');
R = rec(R, 'JSON timestamps ISO-8601 UTC with ms', okTs && strcmp(pk.records(1).timestamp, '2026-10-02T12:00:01.000Z'), pk.records(1).timestamp);

%% Report
nPass = sum(cell2mat(R(:, 2)));
fprintf('\nTeam S2 tests\n');
for k = 1:size(R, 1)
    if R{k, 2}, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('  [%s] %s', tag, R{k, 1});
    if ~isempty(R{k, 3}), fprintf('   (%s)', R{k, 3}); end
    fprintf('\n');
end
fprintf('%d / %d passed\n\n', nPass, size(R, 1));

ok = nPass == size(R, 1);
if nargout == 0 && ~ok
    error('test_S2:failed', '%d S2 test(s) failed.', size(R, 1) - nPass);
end
end

% ========================================================================
function R = rec(R, name, pass, detail)
R(end+1, :) = {name, logical(pass), char(string(detail))};
end

function R = tryOdd(R)
threw = false;
try
    songdo.acoustic.design_fir_lowpass(100, 3600, 48000);
catch ME
    threw = strcmp(ME.identifier, 'songdo:acoustic:evenLength');
end
R = rec(R, 'FIR rejects even length', threw, '');
end
