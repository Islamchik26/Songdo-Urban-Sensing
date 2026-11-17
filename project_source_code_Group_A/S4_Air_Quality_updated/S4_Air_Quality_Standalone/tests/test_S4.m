% TEST_S4  Unit and numerical tests for Team S4 scenarios S4-1 ... S4-5.
%   cd tests; test_S4
% S4-4 has its own self-tests (assert block in S4_4_cai_categorization.m);
% here S4-5 runs on the committed S4-4 reference CSV so the suite is fast.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
tmp = tempname;  mkdir(tmp);
nPass = 0;  nFail = 0;

r1 = s4_1_sensor(false, tmp);
r2 = s4_2_adc(false, tmp);
r3 = s4_3_filter(false, tmp);
r5 = s4_5_benchmark_export(fullfile(root,'data','S4_4_telemetry_reference.csv'), r3, tmp, false);

T = {
 % ---- S4-1
 'S4-1 ZOH discretization exact (PM2.5)',     r1.pm25.zoh_err < 1e-9
 'S4-1 ZOH discretization exact (CO2)',       r1.co2.zoh_err  < 1e-9
 'S4-1 t63 equals tau (PM2.5)',               abs(r1.pm25.t63 - r1.pm25.tau) < 0.05
 'S4-1 t10-90 = tau*ln 9 (CO2)',              abs(r1.co2.t1090 - r1.co2.tau*log(9)) < 0.1
 'S4-1 2 % settling = tau*ln 50 (CO2)',       abs(r1.co2.ts2 - r1.co2.tau*log(50)) < 0.2
 'S4-1 tau identified within 5 % (PM2.5)',    abs(r1.pm25.tau_hat/r1.pm25.tau - 1) < 0.05
 'S4-1 tau identified within 5 % (CO2)',      abs(r1.co2.tau_hat/r1.co2.tau - 1) < 0.05
 % ---- S4-2
 'S4-2 12-bit LSB = 3.3/4096 V',              abs(r2.lsb_V - 3.3/4096) < 1e-12
 'S4-2 CO2 resolution about 1 ppm/LSB',       abs(r2.lsb_co2 - 1.007) < 0.01
 'S4-2 |quantization error| <= LSB/2',        r2.err_max <= r2.lsb_V/2 + 1e-12
 'S4-2 error std = LSB/sqrt(12) (+-3 %)',     abs(r2.err_std/(r2.lsb_V/sqrt(12)) - 1) < 0.03
 'S4-2 SQNR within 0.5 dB of 6.02B+1.76',     r2.sqnr_maxdev < 0.5
 'S4-2 SQNR monotonic in B',                  all(diff(r2.sqnr) > 5)
 'S4-2 alias 0.95 Hz -> 0.05 Hz',             abs(r2.f_alias_meas - 0.05) < 1e-3
 'S4-2 boxcar AA matches theory (+-1 dB)',    abs(r2.aa_atten_dB - r2.aa_atten_theory_dB) < 1
 'S4-2 boxcar AA attenuates >= 20 dB',        r2.aa_atten_dB <= -20
 % ---- S4-3
 'S4-3 FIR symmetric (linear phase)',         max(abs(r3.h - flipud(r3.h))) < 1e-15
 'S4-3 FIR unity DC gain',                    abs(sum(r3.h) - 1) < 1e-12
 'S4-3 FIR stopband >= 50 dB',                r3.stop_atten_dB >= 50
 'S4-3 group delay = (M-1)/2',                abs(r3.group_delay_samples - (r3.M-1)/2) < 0.01
 'S4-3 FIR streaming == batch',               r3.stream_err_fir < 1e-9
 'S4-3 IIR DF-II streaming == filter()',      r3.stream_err_iir < 1e-9
 'S4-3 FIR reduces RMS error > 2x',           r3.rms_fir < r3.rms_raw/2
 'S4-3 no start-up transient',                abs(r3.co2_fir(1) - r3.co2_raw(1)) < 1e-9
 % ---- S4-5
 'S4-5 all 72 hours matched to AirKorea',     r5.n_matched == 72
 'S4-5 PM2.5 correlation r > 0.95',           r5.pm25.r > 0.95
 'S4-5 PM2.5 RMSE < 5 ug/m3',                 r5.pm25.rmse < 5
 'S4-5 grade agreement >= 80 %',              r5.grade_agreement >= 0.80
 'S4-5 completeness rule (>= 75 %)',          r5.completeness_ok
 'S4-5 JSON schema + 4 channels x 72 h',      r5.schema_ok && r5.n_records == 288
 'S4-5 AirKorea mock written',                exist(fullfile(root,'data','airkorea_131233_mock.json'),'file') == 2
};

fprintf('\n===== test_S4 =====\n');
for k = 1:size(T,1)
    if T{k,2}, nPass = nPass + 1; tag = 'PASS'; else, nFail = nFail + 1; tag = 'FAIL'; end
    fprintf('[%s] %s\n', tag, T{k,1});
end
fprintf('%d passed, %d failed\n', nPass, nFail);
rmdir(tmp, 's');
assert(nFail == 0, 'test_S4: %d test(s) failed', nFail);
