function C = taskChecks(st, tk, res, R)
%TASKCHECKS  Handbook target vs. measured value for one scenario.
%   C = songdoui.taskChecks(station, task, runResult, registry) returns an
%   N x 4 cell {Check, Target, Measured, Result}. Values are taken from the
%   member's own run (returned structs, console text, figure data or the
%   exported JSON); nothing is recomputed with different DSP.

C = cell(0, 4);
if ~tk.implemented
    C = add(C, 'Scenario implemented', 'member code', 'not in midterm submission', 'MISSING');
    return
end
if isempty(res)
    C = add(C, 'Member pipeline executed', 'run', 'not run yet', 'PENDING');
    return
end
C = add(C, 'Member pipeline executed', 'no error', sprintf('%.1f s', res.elapsed), pf(res.ok));
if ~res.ok, return; end

try
    switch tk.id
        % ---------------------------------------------------------- S1
        case 'S1-1'
            m = res.data.metrics;
            C = add(C, 'ZOH pole a = e^{-Ts/tau}', '0.99377', sprintf('%.5f', m.pir_a), pf(abs(m.pir_a - 0.99377) < 1e-4));
            C = add(C, 'ZOH gain b = K(1-a)', '0.01557', sprintf('%.5f', m.pir_b), pf(abs(m.pir_b - 0.01557) < 1e-4));
            C = add(C, 'Pole inside unit circle |a| < 1', '< 1', sprintf('%.5f', abs(m.pir_a)), pf(abs(m.pir_a) < 1));
            C = add(C, '10-90 % rise time', '1.76 s', sprintf('%.3f s', m.pir_rise_time_s), pf(abs(m.pir_rise_time_s - 1.76) < 0.01));
            C = add(C, '2 % settling time 4*tau', '3.2 s', sprintf('%.2f s', m.pir_settling_time_s), pf(abs(m.pir_settling_time_s - 3.2) < 1e-9));
            C = add(C, 'DC gain of discrete model b/(1-a)', '2.5', sprintf('%.4f', m.pir_b/(1 - m.pir_a)), pf(abs(m.pir_b/(1 - m.pir_a) - 2.5) < 1e-6));
        case 'S1-2'
            m = res.data.metrics; q = 3.3/4096;
            C = add(C, 'ADC step q = 3.3/2^12', sprintf('%.4f mV', 1e3*q), sprintf('%.4f mV', 1e3*m.adc_step_v), pf(abs(m.adc_step_v - q) < 1e-12));
            C = add(C, 'Theoretical SQNR 6.02B + 1.76', '74.0 dB', sprintf('%.2f dB', m.sqnr_db), pf(abs(m.sqnr_db - 74) < 0.05));
            ratio = m.quantization_error_variance / m.quantization_theory_variance;
            C = add(C, 'Measured error variance / (q^2/12)', '~1.0', sprintf('%.3f', ratio), pf(abs(ratio - 1) < 0.15));
            C = add(C, 'Max |quantization error| <= q/2', sprintf('%.4f mV', 1e3*q/2), sprintf('%.4f mV', 1e3*max(abs(res.data.quantizationError))), ...
                pf(max(abs(res.data.quantizationError)) <= q/2 + 1e-10));
        case 'S1-3'
            m = res.data.metrics;
            C = add(C, 'Accepted entries (gamma_H 0.75, N_dur 15)', '> 0', sprintf('%d', m.total_entries), pf(m.total_entries > 0));
            C = add(C, 'Accepted exits', '> 0', sprintf('%d', m.total_exits), pf(m.total_exits > 0));
            C = add(C, 'Net occupancy C_in - C_out at end', 'info', sprintf('%d people', res.data.netCount(end)), 'INFO');
        case 'S1-4'
            d = res.data;
            logicOk = all(d.surgeAlarm == ((d.density > 2.5) | (d.densityRate > 0.3)));
            C = add(C, 'Density = C_net / 250 m^2', 'exact', sprintf('max err %.1e', max(abs(d.density - d.netCount/250))), pf(max(abs(d.density - d.netCount/250)) < 1e-12));
            C = add(C, 'Peak density', 'alarm > 2.5', sprintf('%.3f people/m^2', max(d.density)), 'INFO');
            C = add(C, 'Max smoothed d(rho)/dt', 'alarm > 0.3', sprintf('%.4f', max(d.densityRate)), 'INFO');
            C = add(C, 'Alarm logic rho>2.5 OR rate>0.3', 'consistent', sprintf('active %.1f %% of run', 100*mean(d.surgeAlarm)), pf(logicOk));
        % ---------------------------------------------------------- S2
        case {'S2-1', 'S2-2', 'S2-3', 'S2-4', 'S2-5'}
            T = res.data.Checks;
            sel = startsWith(T.Name, tk.id);
            for k = find(sel).'
                C = add(C, char(extractAfter(string(T.Name{k}), strlength(tk.id) + 1)), 'member check', T.Detail{k}, pf(T.Pass(k)));
            end
            if strcmp(tk.id, 'S2-5')
                C = add(C, 'Daytime Leq (NoiseLab)', '65-68 dBA', sprintf('%.1f dBA', res.data.LeqDayDBA), pf(res.data.LeqDayDBA >= 65 && res.data.LeqDayDBA <= 68));
            end
        % ---------------------------------------------------------- S3
        case 'S3-1'
            rep = res.data.report;
            C = add(C, 'Raw t50 delay (PT100, tau 12 s)', 'info', sprintf('%.2f s', rep.raw_delay_seconds), 'INFO');
            C = add(C, 'Compensated t50 delay', 'info', sprintf('%.2f s', rep.compensated_delay_seconds), 'INFO');
            C = add(C, 'Delay reduction', '>= 65 %', sprintf('%.1f %%', rep.delay_reduction_percent), pf(rep.delay_reduction_percent >= 65));
        case 'S3-2'
            vw = res.data.views;
            C = add(C, '10 s vector-mean window', '100 samples @ 10 Hz', 'defaultConfig.windMeanSeconds = 10', 'INFO');
            C = add(C, 'Peak 3 s gust', 'detected', sprintf('%.2f m/s', vw.maxGust), pf(vw.maxGust > 0));
        case 'S3-3'
            fl = res.data.views.humidityFlags;
            C = add(C, 'Corrupted samples flagged', '> 0', sprintf('DROPOUT %d, SUSPECT_JUMP %d', fl.DROPOUT, fl.SUSPECT_JUMP), pf(fl.DROPOUT + fl.SUSPECT_JUMP > 0));
            C = add(C, 'GOOD samples', 'majority', sprintf('%d', fl.GOOD), pf(fl.GOOD > fl.DROPOUT + fl.SUSPECT_JUMP));
        case 'S3-4'
            fac = res.data.views.pressureFactor;
            expect = (1 - 0.0065*6.2/288.15)^(-9.80665*0.0289644/(8.3144598*0.0065));
            C = add(C, 'Hypsometric factor P0/Psta (h = 6.2 m)', sprintf('%.6f', expect), sprintf('%.6f', fac), pf(abs(fac - expect) < 1e-6));
        case 'S3-5'
            C = jsonRow(C, st, R);
            kma = res.data.kma;
            C = add(C, 'Real KMA station 512 rows replayed', '> 0, no interpolation', sprintf('%d rows', kma.row_count), pf(kma.row_count > 0));
        % ---------------------------------------------------------- S4
        case 'S4-4'
            txt = res.console;
            C = add(C, 'Embedded self-tests (schema, FIR, CAI breakpoints, hysteresis)', 'all pass', ...
                yesno(contains(txt, 'All self-tests passed')), pf(contains(txt, 'All self-tests passed')));
            tok = regexp(txt, 'raw:\s*(\d+)\s*\|\s*1-h MA:\s*(\d+)\s*\|\s*1-h MA \+ hysteresis:\s*(\d+)', 'tokens', 'once');
            if ~isempty(tok)
                n = str2double(tok);
                C = add(C, 'Grade transitions raw -> MA -> MA+hysteresis', 'decreasing', sprintf('%d -> %d -> %d', n), pf(n(1) > n(2) && n(2) >= n(3)));
            end
            tok = regexp(txt, 'Streaming vs batch max error:\s*([\d.eE+-]+)', 'tokens', 'once');
            if ~isempty(tok)
                e = str2double(tok{1});
                C = add(C, 'Block streaming (zi->zf) == batch', '< 1e-10', sprintf('%.1e', e), pf(e < 1e-10));
            end
            tok = regexp(txt, 'Peak CAI:\s*(\d+)\s*\(([^)]+)\)', 'tokens', 'once');
            if ~isempty(tok), C = add(C, 'Peak CAI', 'info', sprintf('%s (%s)', tok{1}, tok{2}), 'INFO'); end
            C = jsonRow(C, st, R);
        % ---------------------------------------------------------- S5
        case 'S5-1'
            [raw, filt] = s5Lines(res, 'S5-1', 'Raw', 'Causal');
            hp = @(x) x - movmean(x, 601);
            r = std(hp(raw(1000:end))) / std(hp(filt(1000:end)));
            C = add(C, 'FIR length / cutoff', 'N = 61, fc = 0.05 Hz', regexpOr(res.console, 'Filter Order N = \d+, Cutoff = [\d.]+ Hz'), 'INFO');
            C = add(C, 'Group delay (N-1)/2', '30 samples', regexpOr(res.console, 'Group Delay = \d+ samples'), pf(contains(res.console, 'Group Delay = 30')));
            C = add(C, 'Wave/chop residual reduction', '> 5x', sprintf('%.1fx', r), pf(r > 5));
        case 'S5-2'
            [raw, filt] = s5Lines(res, 'S5-2', 'Raw', 'Peak');
            ratio = max(filt) / max(raw);
            C = add(C, 'Peak preservation max(filtered)/max(raw)', '> 0.85', sprintf('%.3f', ratio), pf(ratio > 0.85));
            C = add(C, 'Pulses above MEIS 15 NTU detected', 'yes', sprintf('%.0f s above limit', sum(filt > 15)), pf(any(filt > 15)));
        case 'S5-3'
            [~, sal] = s5Lines(res, 'S5-3', 'Raw', 'Compensated');
            inBand = mean(sal >= 26 & sal <= 32);
            C = add(C, 'Compensated salinity inside [26, 32] PSU', '> 95 %', sprintf('%.1f %%', 100*inBand), pf(inBand > 0.95));
        case 'S5-4'
            ax = s5Axes(res, 'S5-4');
            ln = findobj(ax, 'Type', 'line');
            [f, P] = deal(ln(end).XData, ln(end).YData);
            m = f > 0.02 & f < 0.25; fm = f(m); Pm = P(m);
            [~, i] = max(Pm);
            C = add(C, 'Dominant tidal peak', sprintf('%.4f cph (M2)', 1/12.42), sprintf('%.4f cph (T = %.2f h)', fm(i), 1/fm(i)), pf(abs(fm(i) - 1/12.42) < 0.02));
        case 'S5-5'
            C = jsonRow(C, st, R);
    end
catch err
    C = add(C, 'Check extraction', 'ok', err.message, 'WARN');
end
end

% -------------------------------------------------------------------------
function C = add(C, name, target, measured, result)
C(end+1, :) = {name, target, measured, result};
end

function s = pf(tf)
if tf, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yesno(tf)
if tf, s = 'passed'; else, s = 'not confirmed'; end
end

function s = regexpOr(txt, pat)
s = regexp(txt, pat, 'match', 'once');
if isempty(s), s = 'n/a'; end
end

function C = jsonRow(C, st, R)
if ~isfile(st.jsonFile)
    C = add(C, 'Sensor Grid JSON (Section 5.3)', 'valid', 'file not found', 'FAIL');
    return
end
v = songdoui.validateSensorGrid(st.jsonFile, R);
C = add(C, 'Sensor Grid JSON schema (Section 5.3)', 'valid', sprintf('%d records, %s', v.nRecords, strjoin(v.channels, ', ')), pf(v.ok));
for k = 1:numel(v.errors),   C = add(C, 'Schema error', '-', v.errors{k}, 'FAIL'); end
for k = 1:numel(v.warnings), C = add(C, 'Schema warning', '-', v.warnings{k}, 'WARN'); end
end

function ax = s5Axes(res, tag)
ax = [];
for f = res.figures(:).'
    if ~isvalid(f), continue; end
    axs = findobj(f, 'Type', 'axes');
    for a = axs(:).'
        if contains(string(a.Title.String), tag), ax = a; return; end
    end
end
error('songdoui:S5', 'Axes for %s not found', tag);
end

function [a, b] = s5Lines(res, tag, nameA, nameB)
ax = s5Axes(res, tag);
ln = findobj(ax, 'Type', 'line');
names = string({ln.DisplayName});
ia = find(contains(names, nameA), 1);
ib = find(contains(names, nameB), 1);
a = ln(ia).YData(:);
b = ln(ib).YData(:);
end
