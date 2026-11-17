function results = run_S2(varargin)
%RUN_S2  Team S2 (Traffic Sound & Acoustic Fleet) - scenarios S2-1 ... S2-5.
%
%   run_S2;                      % run everything, make figures, write JSON
%   r = run_S2('Plot', false);   % headless
%   r = run_S2('Post', true);    % also POST to the Python mock receiver
%
%   Name/value options
%     Plot    logical, default true    draw figures
%     Export  logical, default true    write integration/S2_technopark_acoustic_telemetry.json
%     Post    logical, default false   POST the packet via songdo.io.mock_downstream_post
%
%   Station STATION_TECHNOPARK_ACOUSTIC (37.3820 N, 126.6560 E, 9.0 m)
%   Base MATLAB only. All streaming-path processing is causal (no filtfilt).
%
%   S2-1  60 Hz notch (Q=30) + 101-tap FIR (3.6 kHz) + decimate 48k -> 8k
%   S2-2  A-weighting, bilinear 6th-order IIR (3 biquads) at 8 kHz
%   S2-3  rolling Leq (1 s), SPL (100 ms), Hann STFT (512, 50 % overlap),
%         spectral centroid and >2.5 kHz energy ratio
%   S2-4  siren detector: eta = E[600,1000]/E[100,4000] + Schmitt (0.55/0.35)
%   S2-5  Sensor Grid JSON export, quality flags, NoiseLab 65-68 dBA check

ip = inputParser;
addParameter(ip, 'Plot',   true);
addParameter(ip, 'Export', true);
addParameter(ip, 'Post',   false);
parse(ip, varargin{:});
opt = ip.Results;

thisDir = fileparts(mfilename('fullpath'));
addpath(thisDir);

p0     = 20e-6;
checks = cell(0, 3);

fprintf('\n=== Songdo Urban Sensing - Team S2 (Technopark acoustic) ===\n');

%% Fixture and chain ------------------------------------------------------
fx    = songdo.acoustic.make_s2_fixture();
Fs    = fx.Fs;
chain = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity);
FsOut = chain.FsOut;

[pA, xDec] = chain.process(fx.volts);

naive = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity, 'BypassAntiAlias', true);
[~, xNaive] = naive.process(fx.volts);

%% S2-1  hum rejection, anti-aliasing, decimation -------------------------
fprintf('\n[S2-1] Notch + anti-alias FIR + decimation 48 kHz -> %g Hz\n', FsOut);

[nb, na] = songdo.acoustic.design_notch(60, 30, Fs);
vNotch   = filter(nb, na, fx.volts);

seg48 = (2*Fs + 1) : (4*Fs);                 % 2-4 s: background only
seg8  = (2*FsOut + 1) : (4*FsOut);

humBefore  = songdo.acoustic.tone_amplitude(fx.volts(seg48), Fs, 60);
humAfter   = songdo.acoustic.tone_amplitude(vNotch(seg48),   Fs, 60);
humRej_dB  = 20*log10(humBefore / humAfter);
invAmp     = songdo.acoustic.tone_amplitude(fx.volts(seg48), Fs, 18000);
aliasGood  = songdo.acoustic.tone_amplitude(xDec(seg8),   FsOut, 2000);
aliasNaive = songdo.acoustic.tone_amplitude(xNaive(seg8), FsOut, 2000);
aliasGain  = 20*log10(aliasNaive / aliasGood);

fprintf('  60 Hz hum   : %.3e V -> %.3e V   (%.1f dB rejection)\n', humBefore, humAfter, humRej_dB);
fprintf('  18 kHz tone : %.3e V at input; folds to 2 kHz after /6\n', invAmp);
fprintf('  2 kHz alias : %.3e V with FIR, %.3e V without  (%.1f dB better)\n', ...
        aliasGood, aliasNaive, aliasGain);

checks = addCheck(checks, 'S2-1 60 Hz hum rejected >= 40 dB', humRej_dB >= 40, sprintf('%.1f dB', humRej_dB));
checks = addCheck(checks, 'S2-1 no 18 kHz alias at 2 kHz (< 10 uV)', aliasGood < 1e-5, sprintf('%.2e V', aliasGood));
checks = addCheck(checks, 'S2-1 FIR improves alias by >= 40 dB', aliasGain >= 40, sprintf('%.1f dB', aliasGain));
checks = addCheck(checks, 'S2-1 output length = ceil(N/6)', numel(xDec) == ceil(numel(fx.volts)/6), sprintf('%d samples', numel(xDec)));

%% S2-2  A-weighting ------------------------------------------------------
fprintf('\n[S2-2] A-weighting, 6th-order IIR at %g Hz\n', FsOut);

[sos, gA] = songdo.acoustic.design_a_weighting(FsOut);
fTest = [31.5 63 100 125 250 500 1000 2000 3000];
Hdig  = 20*log10(abs(songdo.acoustic.sos_response(sos, gA, fTest, FsOut)));
Hana  = songdo.acoustic.a_weight_db(fTest(:));
aErr  = Hdig - Hana;

fprintf('  %8s %10s %10s %8s\n', 'f [Hz]', 'digital', 'IEC', 'error');
for k = 1:numel(fTest)
    fprintf('  %8.1f %9.2f  %9.2f  %7.2f\n', fTest(k), Hdig(k), Hana(k), aErr(k));
end
fprintf('  NOTE: IEC values are 0.0 dB @ 1 kHz, -19.1 dB @ 100 Hz, +1.2 dB @ 2 kHz, -26.2 dB @ 63 Hz.\n');
fprintf('        The Handbook pairs +1.2 dB with 1 kHz and -26.2 dB with 100 Hz; that is a typo.\n');
fprintf('        Above ~3 kHz an 8 kHz bilinear design droops (see error column).\n');

inBand = fTest >= 63 & fTest <= 2000;
checks = addCheck(checks, 'S2-2 |error| <= 0.5 dB, 63 Hz - 2 kHz', all(abs(aErr(inBand)) <= 0.5), ...
                  sprintf('max %.2f dB', max(abs(aErr(inBand)))));
checks = addCheck(checks, 'S2-2 1 kHz = 0 dB', abs(Hdig(fTest == 1000)) < 0.01, sprintf('%.3f dB', Hdig(fTest == 1000)));
poleMag = zeros(size(sos, 1), 2);
for k = 1:size(sos, 1)
    poleMag(k, :) = abs(roots(sos(k, 4:6))).';
end
checks = addCheck(checks, 'S2-2 all poles inside unit circle', all(poleMag(:) < 1), sprintf('max |p| = %.5f', max(poleMag(:))));

%% S2-3  Leq, SPL, STFT features -----------------------------------------
fprintf('\n[S2-3] Rolling Leq / SPL / STFT features\n');

[splA, tSpl] = songdo.acoustic.level_series(pA, FsOut, 0.1, 0.1);
[leqA, tLeq] = songdo.acoustic.level_series(pA, FsOut, 1.0, 0.1);
F = songdo.acoustic.stft_features(xDec, FsOut);

warm       = FsOut;                                    % skip first 1 s (notch settling)
leqTotal   = 10*log10(mean(pA(warm+1:end).^2) / p0^2);
leqRef     = songdo.acoustic.reference_level_dba(fx.pClean, Fs, fx.t >= 1);
fprintf('  Leq (1-24 s)  chain %.2f dBA   analytic truth %.2f dBA   diff %+.2f dB\n', ...
        leqTotal, leqRef, leqTotal - leqRef);

segs = struct('name', {'background', 'bus rumble', 'siren wail', 'siren yelp'}, ...
              'a',    {1.0, 5.0, 13.0, 19.5}, ...
              'b',    {4.0, 8.0, 16.0, 21.5});
for k = 1:numel(segs)
    i1 = round(segs(k).a*FsOut) + 1;
    i2 = round(segs(k).b*FsOut);
    mF = F.Time >= segs(k).a & F.Time < segs(k).b;
    fprintf('  %-11s  %5.1f dBA   centroid %5.0f Hz   HF(>2.5k) %.3f\n', segs(k).name, ...
            10*log10(mean(pA(i1:i2).^2)/p0^2), mean(F.Centroid(mF)), mean(F.HfRatio(mF)));
end

checks = addCheck(checks, 'S2-3 chain Leq within 0.5 dB of analytic truth', abs(leqTotal - leqRef) <= 0.5, ...
                  sprintf('%+.2f dB', leqTotal - leqRef));

% streaming equivalence: random block sizes must reproduce the batch result
chB   = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity);
sizes = [4800 1000 777 4801 12345 1];
pos   = 0;  kb = 0;  pBlock = zeros(0, 1);
v = fx.volts(1:5*Fs);
while pos < numel(v)
    kb = kb + 1;
    L  = min(sizes(mod(kb - 1, numel(sizes)) + 1), numel(v) - pos);
    pBlock = [pBlock; chB.process(v(pos+1:pos+L))]; %#ok<AGROW>
    pos = pos + L;
end
chRef  = songdo.acoustic.AcousticChain('Sensitivity', fx.Sensitivity);
pBatch = chRef.process(v);
streamErr = max(abs(pBlock - pBatch));
fprintf('  Block streaming vs batch: max |diff| = %.2e Pa over %d blocks\n', streamErr, kb);
checks = addCheck(checks, 'S2-3 block streaming == batch (< 1e-9 Pa)', numel(pBlock) == numel(pBatch) && streamErr < 1e-9, ...
                  sprintf('%.1e Pa', streamErr));

%% S2-4  siren detection --------------------------------------------------
fprintf('\n[S2-4] Siren detector: eta + Schmitt (gH = 0.55, gL = 0.35)\n');

flag = songdo.acoustic.schmitt_trigger(F.SirenRatio, 0.55, 0.35);

isSiren = strcmp({fx.Events.Type}, 'siren');
sirenIv = [[fx.Events(isSiren).Start].', [fx.Events(isSiren).Stop].'];
busEv   = fx.Events(strcmp({fx.Events.Type}, 'rumble'));

holdSec = 0.5;                                   % allow release after the siren ends
inSiren = false(size(F.Time));
for k = 1:size(sirenIv, 1)
    inSiren = inSiren | (F.Time >= sirenIv(k, 1) & F.Time <= sirenIv(k, 2) + holdSec);
end

allDetected = true;
for k = 1:size(sirenIv, 1)
    win = F.Time >= sirenIv(k, 1) & F.Time <= sirenIv(k, 2) + holdSec;
    idx = find(flag == 1 & win, 1, 'first');
    if isempty(idx)
        allDetected = false;
        fprintf('  siren %d (%.0f-%.0f s): NOT detected\n', k, sirenIv(k, :));
    else
        fprintf('  siren %d (%.0f-%.0f s): detected, latency %.2f s\n', k, sirenIv(k, :), F.Time(idx) - sirenIv(k, 1));
    end
end
busFrames = F.Time >= busEv.Start & F.Time <= busEv.Stop;
busFalse  = sum(flag(busFrames) == 1);
outFalse  = sum(flag == 1 & ~inSiren);
fprintf('  eta during bus rumble: max %.2f   false frames: bus %d, elsewhere %d\n', ...
        max(F.SirenRatio(busFrames)), busFalse, outFalse);

checks = addCheck(checks, 'S2-4 both sirens detected', allDetected, '');
checks = addCheck(checks, 'S2-4 zero false triggers on bus rumble', busFalse == 0, sprintf('%d frames', busFalse));
checks = addCheck(checks, 'S2-4 zero false triggers outside sirens', outFalse == 0, sprintf('%d frames', outFalse));

%% S2-5  telemetry export, quality flags, NoiseLab check ------------------
fprintf('\n[S2-5] Sensor Grid telemetry + NoiseLab benchmark\n');

t0 = datetime(2026, 10, 2, 12, 0, 0, 'TimeZone', 'UTC');

nBlk   = floor(numel(fx.volts) / (0.1*Fs));
tick   = (10:nBlk).';                              % first full 1 s window onwards
tGrid  = tick * 0.1;

rmsRaw  = songdo.acoustic.block_rms(fx.volts, round(0.1*Fs));
rmsFilt = songdo.acoustic.block_rms(xDec,     round(0.1*FsOut));
[splZ, ~] = songdo.acoustic.level_series(xDec / fx.Sensitivity, FsOut, 0.1, 0.1);
[leqZ, ~] = songdo.acoustic.level_series(xDec / fx.Sensitivity, FsOut, 1.0, 0.1);

m = struct();
m.Time       = tGrid;
m.MicRawRms  = rmsRaw(tick);
m.MicFiltRms = rmsFilt(tick);
m.SplZ       = splZ(tick);
m.SplA       = splA(tick);
m.LeqZ       = leqZ(tick - 9);
m.LeqA       = leqA(tick - 9);
m.SirenRatio = interp1(F.Time, F.SirenRatio, tGrid, 'previous', 'extrap');
m.SirenFlag  = interp1(F.Time, flag,         tGrid, 'previous', 'extrap');

jsonText = songdo.acoustic.export_s2_json(m, fx.Station, t0);
pkt      = jsondecode(jsonText);

nRec     = numel(pkt.records);
req      = {'timestamp', 'channel', 'raw_value', 'filtered_value', 'unit', 'quality_flag'};
fieldsOk = all(isfield(pkt.records, req)) && isfield(pkt, 'schema_version') ...
           && strcmp(pkt.station_id, 'STATION_TECHNOPARK_ACOUSTIC');
chanOk   = all(ismember({pkt.records.channel}, ...
                {'MIC_RAW_VOLTS', 'SPL_DBA_100MS', 'LEQ_1S_DBA', 'EVENT_SIREN_FLAG'}));
nonGood  = sum(~strcmp({pkt.records.quality_flag}, 'GOOD'));
fprintf('  %d records on a 100 ms grid, %d not GOOD\n', nRec, nonGood);

checks = addCheck(checks, 'S2-5 JSON schema fields present', fieldsOk && chanOk, sprintf('%d records', nRec));
checks = addCheck(checks, 'S2-5 all records GOOD on clean fixture', nonGood == 0, sprintf('%d flagged', nonGood));

% Daytime-equivalent level vs NoiseLab baseline (65-68 dBA)
fprintf('  Daytime Leq over fixture: %.1f dBA   (NoiseLab Technopark baseline 65-68 dBA)\n', leqTotal);
fprintf('  The fixture is synthetic and was built to land in that band, so this checks\n');
fprintf('  the chain end-to-end, not the real street.\n');
checks = addCheck(checks, 'S2-5 Leq within NoiseLab 65-68 dBA', leqTotal >= 65 && leqTotal <= 68, sprintf('%.1f dBA', leqTotal));

outFile = '';
if opt.Export
    outDir = fullfile(thisDir, '..', 'integration');
    if ~isfolder(outDir)
        mkdir(outDir);
    end
    outFile = fullfile(outDir, 'S2_technopark_acoustic_telemetry.json');
    fid = fopen(outFile, 'w');
    fprintf(fid, '%s', jsonText);
    fclose(fid);
    fprintf('  Wrote %s\n', outFile);
end

if opt.Post
    try
        cfg    = songdo.core.get_project_config();
        status = songdo.io.mock_downstream_post(cfg.network.mock_ingest_url, jsonText);
        fprintf('  POST status: %s\n', string(status));
        checks = addCheck(checks, 'S2-5 mock receiver accepted packet', isequal(status, 200) || strcmp(string(status), "200"), string(status));
    catch ME
        fprintf('  POST failed: %s\n', ME.message);
        checks = addCheck(checks, 'S2-5 mock receiver accepted packet', false, ME.message);
    end
end

%% Figures ----------------------------------------------------------------
if opt.Plot
    figure('Name', 'S2-1 spectra (2-4 s)', 'Color', 'w');
    [f1, A1] = songdo.acoustic.amp_spectrum(fx.volts(seg48), Fs);
    [f2, A2] = songdo.acoustic.amp_spectrum(xDec(seg8),   FsOut);
    [f3, A3] = songdo.acoustic.amp_spectrum(xNaive(seg8), FsOut);
    subplot(3, 1, 1);  plot(f1, 20*log10(A1 + 1e-12)); grid on;
    title('Raw mic, 48 kHz: 60 Hz hum and 18 kHz inverter tone'); ylabel('dBV'); xlim([0 24000]);
    subplot(3, 1, 2);  plot(f2, 20*log10(A2 + 1e-12)); grid on;
    title('Notch + FIR + decimate: no alias'); ylabel('dBV'); xlim([0 FsOut/2]); ylim([-160 -20]);
    subplot(3, 1, 3);  plot(f3, 20*log10(A3 + 1e-12)); grid on;
    title('Decimate without anti-alias FIR: 18 kHz folds to 2 kHz'); ylabel('dBV'); xlabel('Hz');
    xlim([0 FsOut/2]); ylim([-160 -20]);

    figure('Name', 'S2-2 A-weighting', 'Color', 'w');
    fa = logspace(log10(20), log10(3900), 400).';
    semilogx(fa, a_db(fa), 'k-', fa, 20*log10(abs(songdo.acoustic.sos_response(sos, gA, fa, FsOut))), 'r--');
    grid on; legend('IEC analytic', 'IIR at 8 kHz', 'Location', 'southeast');
    xlabel('Hz'); ylabel('dB'); title('A-weighting'); ylim([-60 5]);

    figure('Name', 'S2-3 levels and STFT features', 'Color', 'w');
    subplot(3, 1, 1);  plot(tSpl, splA, tLeq, leqA, 'LineWidth', 1.2); grid on;
    legend('SPL 100 ms', 'Leq 1 s'); ylabel('dBA'); title('Sound level');
    subplot(3, 1, 2);  plot(F.Time, F.Centroid); grid on; ylabel('Hz'); title('Spectral centroid');
    subplot(3, 1, 3);  plot(F.Time, F.HfRatio);   grid on; ylabel('ratio'); xlabel('s');
    title('Energy above 2.5 kHz / total');

    figure('Name', 'S2-4 siren detector', 'Color', 'w');
    plot(F.Time, F.SirenRatio, 'b-', F.Time, 0.9*flag, 'r-', 'LineWidth', 1.1); hold on;
    plot([0 fx.Duration], [0.55 0.55], 'k--', [0 fx.Duration], [0.35 0.35], 'k:');
    for k = 1:size(sirenIv, 1)
        patch(sirenIv(k, [1 2 2 1]), [0 0 1 1], [1 0.8 0.8], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    end
    patch([busEv.Start busEv.Stop busEv.Stop busEv.Start], [0 0 1 1], [0.8 0.8 1], 'FaceAlpha', 0.3, 'EdgeColor', 'none');
    hold off; grid on; ylim([0 1]); xlabel('s'); ylabel('\eta');
    legend('\eta = E[600,1000]/E[100,4000]', 'EVENT\_SIREN\_FLAG (x0.9)', '\gamma_H', '\gamma_L', 'Location', 'northwest');
    title('Siren (red) vs diesel bus rumble (blue)');
end

%% Summary ----------------------------------------------------------------
nPass = sum(cellfun(@(x) x, checks(:, 2)));
fprintf('\n--- S2 checks ---\n');
for k = 1:size(checks, 1)
    if checks{k, 2}, tag = 'PASS'; else, tag = 'FAIL'; end
    fprintf('  [%s] %s   %s\n', tag, checks{k, 1}, checks{k, 3});
end
fprintf('S2: %d / %d checks passed\n\n', nPass, size(checks, 1));

results = struct();
results.Checks    = cell2table(checks, 'VariableNames', {'Name', 'Pass', 'Detail'});
results.AllPassed = nPass == size(checks, 1);
results.LeqDayDBA = leqTotal;
results.Telemetry = outFile;
results.Features  = F;
results.SirenFlag = flag;
end

% ========================================================================
function checks = addCheck(checks, name, pass, detail)
checks(end+1, :) = {name, logical(pass), char(string(detail))};
end

function y = a_db(f)
y = songdo.acoustic.a_weight_db(f);
end
