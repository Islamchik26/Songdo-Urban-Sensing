function r = s4_3_filter(doPlot, outDir)
% S4-3  Causal filter design for the NDIR CO2 channel (street canyon, 3 days).
%   Chain: true CO2 -> first-order sensor (S4-1) -> 12-bit ADC (S4-2) -> filter
%   (a) Hamming windowed-sinc low-pass FIR, M = 241 taps, linear phase
%   (b) First-order IIR (EMA) in Direct Form II (transposed), same smoothing time scale
%   Both run block-by-block with persistent state (zi -> zf); compared to batch.
if nargin < 1, doPlot = true; end
if nargin < 2, outDir = pwd; end
rng(7);

Ts = 10;  Fs = 1/Ts;                         % CO2 sensor output every 10 s
N  = 3*24*3600/Ts;                           % 25 920 samples = 3 days
t  = (0:N-1)'*Ts;  th = t/3600;  hod = mod(th, 24);

% ---- synthetic street-canyon CO2 [ppm] -------------------------------------
co2_true = 425 ...
    + 15*cos(2*pi*(hod - 4)/24) ...                          % nocturnal boundary layer
    + 70*exp(-(hod - 8.5).^2/(2*1.0^2)) ...                  % morning rush
    + 55*exp(-(hod - 18.5).^2/(2*1.2^2)) ...                 % evening rush
    + 40*exp(-(th - 58).^2/(2*5^2));                         % day-3 stagnation (same as S4-4 haze)
co2_true = co2_true + 12*double(mod(t, 900) < 60);           % bus idling at stop every 15 min

% sensor (tau = 25 s, exact ZOH) + NDIR noise + 12-bit ADC
K = 1.6/2000;  V0 = 0.4;  a = exp(-Ts/25);
v = filter((1-a)*[0 1], [1 -a], K*co2_true + V0, K*co2_true(1) + V0);   % zi = steady state
v = v + K*8*randn(N,1);                                      % 8 ppm rms NDIR noise
D = 3.3/2^12;  v = D*round(v/D);
co2_raw = (v - V0)/K;

% ---- (a) windowed-sinc FIR --------------------------------------------------
M  = 241;  fc = 0.02;                        % cutoff, cycles/sample (= 1/500 s)
m  = (0:M-1)' - (M-1)/2;
h  = 2*fc*sinc0(2*fc*m) .* (0.54 - 0.46*cos(2*pi*(0:M-1)'/(M-1)));
h  = h / sum(h);                             % unity DC gain
r.M = M;  r.fc_hz = fc*Fs;  r.h = h;

% frequency response (base MATLAB DFT evaluation)
f  = linspace(0, 0.5, 4001)';                % cycles/sample
E  = exp(-1j*2*pi*f*(0:M-1));
H  = E*h;
r.f_hz = f*Fs;  r.H_dB = 20*log10(abs(H) + 1e-12);
fStop  = fc + 3.3/M;                         % Hamming transition width
r.stop_atten_dB = -max(r.H_dB(f >= fStop));
ph   = unwrap(angle(H(f > 0 & f < fc/2)));
w    = 2*pi*f(f > 0 & f < fc/2);
pp   = polyfit(w, ph, 1);
r.group_delay_samples = -pp(1);              % theory (M-1)/2 = 120
r.group_delay_s = r.group_delay_samples*Ts;

% ---- (b) first-order IIR, Direct Form II -----------------------------------
tauF  = (M-1)/2*Ts;                          % match FIR delay: 1200 s
alpha = 1 - exp(-Ts/tauF);
bI = alpha;  aI = [1 -(1-alpha)];

% ---- batch vs block streaming (1-h blocks = 360 samples) -------------------
ziF = co2_raw(1)*flipud(cumsum(flipud(h(2:end))));           % steady-state IC
ziI = (1-alpha)*co2_raw(1);
fir_b = filter(h, 1, co2_raw, ziF);
iir_b = filter(bI, aI, co2_raw, ziI);

L = 360;  fir_s = zeros(N,1);  iir_s = zeros(N,1);  zF = ziF;  zI = ziI;
for k = 1:L:N
    idx = k:min(k+L-1, N);
    [fir_s(idx), zF] = filter(h, 1, co2_raw(idx), zF);
    [iir_s(idx), zI] = dfII(bI, aI, co2_raw(idx), zI);       % hand-written DF-II(T)
end
r.stream_err_fir = max(abs(fir_s - fir_b));
r.stream_err_iir = max(abs(iir_s - iir_b));

% ---- noise reduction (compare with delay-aligned truth) --------------------
d   = round(r.group_delay_samples);
ref = [repmat(co2_true(1), d, 1); co2_true(1:end-d)];
sk  = 2*M:N;                                  % skip start-up
r.rms_raw = sqrt(mean((co2_raw(sk) - co2_true(sk)).^2));
r.rms_fir = sqrt(mean((fir_s(sk) - ref(sk)).^2));
r.rms_iir = sqrt(mean((iir_s(sk) - co2_true(sk)).^2));
r.t = t;  r.co2_true = co2_true;  r.co2_raw = co2_raw;  r.co2_fir = fir_s;  r.co2_iir = iir_s;

fprintf('\n--- S4-3 Causal filter design (CO2, Ts = %d s) ---\n', Ts);
fprintf('FIR: M = %d, fc = %.4f Hz (%.0f s), stopband >= %.1f dB, group delay %.1f samples = %.1f min\n', ...
    M, r.fc_hz, 1/r.fc_hz, r.stop_atten_dB, r.group_delay_samples, r.group_delay_s/60);
fprintf('Streaming vs batch: FIR %.1e, IIR(DF-II) %.1e\n', r.stream_err_fir, r.stream_err_iir);
fprintf('RMS error vs truth: raw %.2f ppm | FIR (delay-aligned) %.2f ppm | IIR %.2f ppm\n', r.rms_raw, r.rms_fir, r.rms_iir);

if doPlot
    fig = figure('Name','S4-3 CO2 filter','Position',[100 100 1200 650]);
    subplot(2,2,[1 2]); hold on; grid on;
    plot(th, co2_raw, 'Color',[0.75 0.75 0.75]);
    plot(th, co2_true, 'k', 'LineWidth',1);
    plot(th, fir_s, 'b', 'LineWidth',1.4);
    plot(th, iir_s, 'Color',[0.85 0.33 0.1], 'LineWidth',1.2);
    xlim([0 72]); xlabel('Time [h]'); ylabel('CO_2 [ppm]');
    title('S4-3: NDIR CO_2 — raw (sensor + 12-bit ADC) vs causal FIR / IIR');
    legend('raw','true','FIR M=241','IIR DF-II','Location','northwest');
    subplot(2,2,3);
    plot(r.f_hz*1e3, r.H_dB, 'b'); grid on; ylim([-100 5]);
    xlabel('Frequency [mHz]'); ylabel('|H| [dB]');
    title(sprintf('FIR magnitude, stopband %.0f dB', r.stop_atten_dB));
    subplot(2,2,4);
    stem((0:M-1)*Ts/60, h, 'Marker','none'); grid on;
    xlabel('Lag [min]'); ylabel('h[n]'); title('Impulse response (symmetric)');
    print(fig, fullfile(outDir,'S4_3_co2_filter.png'), '-dpng', '-r150');
end
end

function [y, z] = dfII(b, a, x, z)
% First-order Direct Form II (transposed): y[n] = b0*x[n] + z, z <- -a1*y[n].
% One delay element; state z is interchangeable with filter()'s zi/zf.
y = zeros(size(x));
for n = 1:numel(x)
    y(n) = b(1)*x(n) + z;
    z    = -a(2)*y(n);
end
end

function y = sinc0(x)
y = ones(size(x));  k = x ~= 0;
y(k) = sin(pi*x(k)) ./ (pi*x(k));
end
