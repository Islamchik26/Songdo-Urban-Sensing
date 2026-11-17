function r = s4_2_adc(doPlot, outDir)
% S4-2  ADC sampling, aliasing and mid-tread quantization.
%   (a) 12-bit, 3.3 V mid-tread quantizer: LSB in physical units for PM2.5 / CO2
%   (b) SQNR sweep B = 6..16 vs the 6.02*B + 1.76 dB rule
%   (c) aliasing of a 0.95 Hz sensor-fan ripple sampled at 1 Hz -> 0.05 Hz,
%       and its suppression by 10x oversampling + 1-s block averaging.
if nargin < 1, doPlot = true; end
if nargin < 2, outDir = pwd; end

Vref = 3.3;  B = 12;
D    = Vref / 2^B;                                   % LSB [V]
r.lsb_V    = D;
r.lsb_pm25 = D / 0.0033;                             % ug/m3 per LSB (S4-1 gain)
r.lsb_co2  = D / (1.6/2000);                         % ppm per LSB

% (b) SQNR sweep with a near-full-scale, non-commensurate sine
Ns = 2^15;  n = (0:Ns-1)';
Bs = 6:16;  sq = zeros(size(Bs));
for k = 1:numel(Bs)
    Dk = Vref / 2^Bs(k);
    x  = Vref/2 + (Vref/2 - Dk)*sin(2*pi*0.1234567*n);
    e  = quantize(x, Dk, Bs(k)) - x;
    sq(k) = 10*log10(var(x) / var(e));
end
r.B = Bs;  r.sqnr = sq;  r.sqnr_theory = 6.02*Bs + 1.76;
r.sqnr_maxdev = max(abs(sq - r.sqnr_theory));

% quantization error statistics at 12 bit on a real-like CO2 voltage
xc = 0.4 + 0.8*(0.5 + 0.4*sin(2*pi*n/5000) + 0.05*sin(2*pi*n/37));
ec = quantize(xc, D, B) - xc;
r.err_max  = max(abs(ec));                           % should be <= D/2
r.err_std  = std(ec);                                % theory D/sqrt(12)

% (c) aliasing
Fa   = 10;  Fs = 1;  T = 600;                        % analog sim 10 Hz, ADC 1 Hz
ta   = (0:1/Fa:T-1/Fa)';
fRip = 0.95;
pm   = 25 + 5*sin(2*pi*ta/300);                      % slow PM variation
xa   = pm + 3*sin(2*pi*fRip*ta);                     % + fan ripple [ug/m3]
dec  = Fa/Fs;
xs_naive = xa(1:dec:end);                            % sample-and-hold, no AA
xs_avg   = mean(reshape(xa, dec, []), 1)';           % 1-s block average (boxcar AA)
ts       = ta(1:dec:end);
pmS      = 25 + 5*sin(2*pi*ts/300);
pmA      = mean(reshape(pm, dec, []), 1)';

r.f_alias_theory = abs(fRip - Fs*round(fRip/Fs));
[r.f_alias_meas, r.amp_naive] = peakTone(xs_naive - pmS, Fs);
[~,              r.amp_avg]   = peakTone(xs_avg  - pmA, Fs);
r.aa_atten_dB = 20*log10(r.amp_avg / r.amp_naive);
r.aa_atten_theory_dB = 20*log10(abs(sin(pi*fRip*dec/Fa) / (dec*sin(pi*fRip/Fa))));

fprintf('\n--- S4-2 ADC sampling, aliasing, quantization ---\n');
fprintf('12-bit LSB = %.3f mV = %.3f ug/m3 (PM2.5) = %.3f ppm (CO2)\n', 1e3*D, r.lsb_pm25, r.lsb_co2);
fprintf('Quant. error: max %.3f LSB (<=0.5), std %.4f LSB (theory %.4f)\n', r.err_max/D, r.err_std/D, 1/sqrt(12));
fprintf('SQNR max deviation from 6.02B+1.76 over B=6..16: %.2f dB\n', r.sqnr_maxdev);
fprintf('Alias of %.2f Hz at Fs=%g Hz: theory %.3f Hz, measured %.3f Hz\n', fRip, Fs, r.f_alias_theory, r.f_alias_meas);
fprintf('Boxcar anti-alias attenuation: %.1f dB (theory %.1f dB)\n', r.aa_atten_dB, r.aa_atten_theory_dB);

if doPlot
    fig = figure('Name','S4-2 ADC','Position',[100 100 1200 420]);
    subplot(1,3,1);
    plot(Bs, sq, 'bo-', Bs, r.sqnr_theory, 'k--'); grid on;
    xlabel('Bits B'); ylabel('SQNR [dB]'); title('SQNR vs 6.02B + 1.76');
    legend('measured','theory','Location','northwest');
    subplot(1,3,2);
    idx = 1:400;
    plot(n(idx), ec(idx)/D, 'b.'); grid on; ylim([-0.6 0.6]);
    xlabel('Sample'); ylabel('Error [LSB]'); title('12-bit mid-tread error');
    subplot(1,3,3); hold on; grid on;
    plot(ta, xa, 'Color',[0.8 0.8 0.8]);
    plot(ts, xs_naive, 'r', 'LineWidth',1.2);
    plot(ts, xs_avg, 'b', 'LineWidth',1.4);
    xlim([0 200]); xlabel('Time [s]'); ylabel('PM_{2.5} [\mug/m^3]');
    title(sprintf('0.95 Hz ripple aliases to %.2f Hz', r.f_alias_meas));
    legend('analog','1 Hz sample (no AA)','1-s average (AA)','Location','southoutside');
    print(fig, fullfile(outDir,'S4_2_adc.png'), '-dpng', '-r150');
end
end

function q = quantize(x, D, B)
% Mid-tread uniform quantizer (zero is a reconstruction level), unipolar ADC.
q = D * min(max(round(x/D), 0), 2^B - 1);
end

function [f, amp] = peakTone(x, Fs)
N = numel(x);  X = abs(fft(x - mean(x)))/N;  X = 2*X(1:floor(N/2)+1);
[amp, i] = max(X(2:end));  f = i*Fs/N;
end
