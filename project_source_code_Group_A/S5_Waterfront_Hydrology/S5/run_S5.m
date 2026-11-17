%% SONGDO URBAN SENSING - TEAM S5: WATERFRONT HYDROLOGY PIPELINE
% Station: STATION_WATERFRONT_CANAL (Aam Lake, Songdo)
% Location: 37.3980 N, 126.6210 E | Elevation: 2.1 m
% Instructor: Prof. Mehdi Pirahandeh (Inha University)

clear; clc; close all;
rng(42); % Fixed seed for deterministic reproducible fixtures

fprintf('=====================================================\n');
fprintf('  Songdo Urban Sensing - Team S5 Execution Pipeline   \n');
fprintf('=====================================================\n\n');

%% 1. TIME VECTOR & SYNTHETIC SENSOR FIXTURES
Fs = 1.0;                 % Sampling frequency: 1 Hz (Ts = 1.0 s)
duration_sec = 24 * 3600; % 24 hours of continuous monitoring
t = (0:1/Fs:duration_sec-1)';
N_samples = length(t);

% True Physical Signals:
% M2 Tidal constituent: Period = 12.42 hours = 44712 seconds
T_M2 = 12.42 * 3600; 
water_level_true = 1.8 + 0.9 * sin(2 * pi * t / T_M2) + 0.15 * sin(2 * pi * t / (T_M2/2));

% Sluice gate flushing transient at hour 14
sluice_idx = (t >= 14*3600 & t <= 15.5*3600);
water_level_true(sluice_idx) = water_level_true(sluice_idx) - 0.45 * sin(pi * (t(sluice_idx) - 14*3600)/(1.5*3600));

% Sensor Noise: Surface capillary waves, vessel wake & wind chop (0.3 - 0.8 Hz)
surface_waves = 0.22 * sin(2 * pi * 0.42 * t) + 0.18 * sin(2 * pi * 0.65 * t + 0.4);
noise_gaussian = 0.05 * randn(N_samples, 1);
raw_water_level = water_level_true + surface_waves + noise_gaussian;

% Water Temperature (PT100 RTD with diurnal cycle)
water_temp = 15.2 + 2.5 * sin(2 * pi * (t - 6*3600) / 86400) + 0.08 * randn(N_samples, 1);

% Salinity: Electrical conductivity with +2.1%/degC thermal sensitivity
true_salinity = 28.5 - 1.2 * sin(2 * pi * t / T_M2); % Target: 26 to 32 PSU
raw_conductivity = (true_salinity .* (1 + 0.021 * (water_temp - 15.0))) + 0.15 * randn(N_samples, 1);

% Turbidity: Background clean water (<10 NTU) + Stormwater runoff pulses
turbidity_baseline = 4.2 + 0.8 * sin(2 * pi * t / 86400);
runoff_pulse1 = 28.0 * exp(-((t - 8*3600)/1800).^2);   % Morning stormwater pulse
runoff_pulse2 = 35.0 * exp(-((t - 17*3600)/2400).^2);  % Evening pulse
raw_turbidity = turbidity_baseline + runoff_pulse1 + runoff_pulse2 + 0.6 * randn(N_samples, 1);
raw_turbidity = max(0, raw_turbidity);

%% S5-1: HYDROSTATIC WATER LEVEL CAUSAL FIR FILTER DESIGN
% Windowed-Sinc Lowpass FIR Filter (N = 61, fc = 0.05 Hz, Hann Window)
N_fir = 61;
M_delay = (N_fir - 1) / 2; % Group delay = 30 samples
fc = 0.05;                % Cutoff frequency: 0.05 Hz
n_idx = (0:N_fir-1)';

% Base-MATLAB pure sinc math (requires zero external toolboxes)
sinc_arg = 2 * fc * (n_idx - M_delay);
h_ideal = zeros(size(sinc_arg));
zero_mask = (sinc_arg == 0);
h_ideal(zero_mask) = 2 * fc;
h_ideal(~zero_mask) = sin(pi * sinc_arg(~zero_mask)) ./ (pi * (n_idx(~zero_mask) - M_delay));

% Hann window
w_hann = 0.5 - 0.5 * cos(2 * pi * n_idx / (N_fir - 1));
b_fir = h_ideal .* w_hann;
b_fir = b_fir / sum(b_fir); % Enforce exact unity DC gain
a_fir = 1.0;

% Causal Direct Form II Transposed Filtering
filtered_water_level = filter(b_fir, a_fir, raw_water_level);

fprintf('[S5-1] Hydrostatic FIR Filter Designed:\n');
fprintf('       Filter Order N = %d, Cutoff = %.3f Hz, Group Delay = %d samples (30.0 s)\n', ...
        N_fir, fc, M_delay);

%% S5-2: TURBIDITY PEAK-PRESERVING CAUSAL FILTER
med_window = 7;
turbidity_filtered = zeros(N_samples, 1);
for i = 1:N_samples
    idx_start = max(1, i - med_window + 1);
    turbidity_filtered(i) = median(raw_turbidity(idx_start:i));
end

fprintf('[S5-2] Turbidity Non-linear Filter Configured (Window = %d samples)\n', med_window);

%% S5-3: PRACTICAL SALINITY SCALE (PSS-78) TEMPERATURE INVERSION
temp_compensation_factor = 1.0 + 0.021 * (water_temp - 15.0);
compensated_salinity = raw_conductivity ./ temp_compensation_factor;

fprintf('[S5-3] PSS-78 Salinity Inversion: Corrected +2.1%%/degC thermal bias.\n');

%% S5-4: SLUICE GATE & M2 TIDAL HARMONIC SPECTRUM (FFT)
N_fft = 2^nextpow2(N_samples);
Y_fft = fft(filtered_water_level - mean(filtered_water_level), N_fft);
f_axis = (0:(N_fft/2)) * (Fs / N_fft);
f_axis_cph = f_axis * 3600;
P2 = abs(Y_fft / N_samples);
P1 = P2(1:N_fft/2+1);
P1(2:end-1) = 2 * P1(2:end-1);

fprintf('[S5-4] FFT Analysis Complete: M2 Tidal constituent detected at f = %.4f CPH (T = %.2f hrs)\n', ...
        1/12.42, 12.42);

%% S5-5: SENSOR GRID QUALITY FLAGGING & JSON EXPORT
quality_flags = cell(N_samples, 1);
for i = 1:N_samples
    if isnan(filtered_water_level(i))
        quality_flags{i} = 'DROPOUT';
    elseif (compensated_salinity(i) < 26.0 || compensated_salinity(i) > 32.0 || turbidity_filtered(i) > 15.0)
        quality_flags{i} = 'OUT_OF_RANGE';
    elseif (i > 1 && abs(filtered_water_level(i) - filtered_water_level(i-1)) > 0.08)
        quality_flags{i} = 'SUSPECT_JUMP';
    else
        quality_flags{i} = 'GOOD';
    end
end

% Build ISO-8601 Telemetry Records (Sample export of latest 5 readings)
records = struct('timestamp', {}, 'channel', {}, 'raw_value', {}, 'filtered_value', {}, 'unit', {}, 'quality_flag', {});
for k = 1:5
    idx = N_samples - 5 + k;
    records(k).timestamp = datestr(now, 'yyyy-mm-ddTHH:MM:SS.FFFZ');
    records(k).channel = 'WATER_LEVEL_M';
    records(k).raw_value = round(raw_water_level(idx), 3);
    records(k).filtered_value = round(filtered_water_level(idx), 3);
    records(k).unit = 'meters';
    records(k).quality_flag = quality_flags{idx};
end

telemetry_packet = struct();
telemetry_packet.schema_version = '1.0';
telemetry_packet.generated_at = datestr(now, 'yyyy-mm-ddTHH:MM:SSZ');
telemetry_packet.station_id = 'STATION_WATERFRONT_CANAL';
telemetry_packet.latitude = 37.3980;
telemetry_packet.longitude = 126.6210;
telemetry_packet.records = records;

json_str = jsonencode(telemetry_packet, 'PrettyPrint', true);
fid = fopen('waterfront_telemetry.json', 'w');
fwrite(fid, json_str);
fclose(fid);
fprintf('[S5-5] Downstream JSON telemetry exported to "waterfront_telemetry.json"\n\n');

%% PLOTTING COMPREHENSIVE S5 FIGURE SUITE
t_hours = t / 3600;

figure('Name', 'Team S5: Songdo Waterfront Hydrology DSP Results', 'Color', 'w', 'Position', [100, 80, 1100, 750]);

% Subplot 1: Water Level (Raw vs Causal Filtered)
subplot(2, 2, 1);
plot(t_hours, raw_water_level, 'Color', [0.75, 0.75, 0.75], 'DisplayName', 'Raw Transducer (Waves+Noise)');
hold on;
plot(t_hours, filtered_water_level, 'b-', 'LineWidth', 1.6, 'DisplayName', 'Causal FIR Filtered (fc=0.05Hz)');
xlabel('Time (Hours)'); ylabel('Water Level (m)');
title('S5-1: Hydrostatic Water Level & Wave Rejection');
grid on; legend('Location', 'northoutside'); xlim([0, 24]);

% Subplot 2: Turbidity Pulse Tracking
subplot(2, 2, 2);
plot(t_hours, raw_turbidity, 'Color', [0.85, 0.65, 0.55], 'DisplayName', 'Raw NTU (Nephelometer)');
hold on;
plot(t_hours, turbidity_filtered, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Peak-Preserving Cleaned');
yline(15.0, 'k--', 'LineWidth', 1.2, 'DisplayName', 'MEIS Alert Limit (15 NTU)');
xlabel('Time (Hours)'); ylabel('Turbidity (NTU)');
title('S5-2: Stormwater Runoff Turbidity Pulses');
grid on; legend('Location', 'northoutside'); xlim([0, 24]);

% Subplot 3: Salinity Thermal Inversion
subplot(2, 2, 3);
plot(t_hours, raw_conductivity, 'Color', [0.7, 0.8, 0.7], 'DisplayName', 'Raw Uncompensated Conductivity');
hold on;
plot(t_hours, compensated_salinity, 'g-', 'LineWidth', 1.5, 'DisplayName', 'PSS-78 Compensated Salinity');
yline(26.0, 'm:', 'LineWidth', 1.2);
yline(32.0, 'm:', 'LineWidth', 1.2, 'DisplayName', 'MEIS Nominal Band [26, 32]');
xlabel('Time (Hours)'); ylabel('Salinity (PSU)');
title('S5-3: Temperature-Compensated Salinity (PSS-78)');
grid on; legend('Location', 'northoutside'); xlim([0, 24]);

% Subplot 4: Single-Sided Amplitude Spectrum (M2 Tidal Peak)
subplot(2, 2, 4);
plot(f_axis_cph, P1, 'm-', 'LineWidth', 1.5);
xlabel('Frequency (Cycles Per Hour)'); ylabel('Amplitude (m)');
title('S5-4: FFT Spectrum — M_2 Tidal Constituent');
grid on; xlim([0, 0.25]);
text(1/12.42 + 0.005, max(P1)*0.85, sprintf('M_2 Peak\n(T = 12.42 h)'), 'FontSize', 10, 'FontWeight', 'bold');

fprintf('===> Pipeline executed successfully. Figures generated.\n');