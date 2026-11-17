# Team S4 — Air Quality & Canyon Dispersion

Station `STATION_TECHNOPARK_AIRQUALITY` (37.3812 N, 126.6620 E, 7.8 m), Techno-Park R&D Strip.
Channels: `PM25_UG_M3`, `PM10_UG_M3`, `CO2_NDIR_PPM`, `AQI_CAI_LEVEL`. Benchmark: AirKorea Songdo #131233.
Base MATLAB only, R2023b or later. Deterministic (fixed RNG seeds). Signals are synthetic.

## Run

```matlab
R = run_S4;                  % S4-1 ... S4-5, figures + exports in output/
R = run_S4('Plot', false);   % headless, R.Checks holds the pass/fail table
R = run_S4('Post', true);    % also POST JSON (start integration/mock_receiver.py first)
cd tests; test_S4            % 31 unit / numerical tests
```

## Scenarios

| ID | What | File | Key results |
|----|------|------|-------------|
| S4-1 | Sensor transduction: optical PM2.5 (τ = 8 s) and NDIR CO₂ (τ = 25 s) as first-order systems, exact ZOH discretization, t63 / t10–90 / 2 % settling, τ identification from a noisy step | `s4_1_sensor.m` | ZOH error ~1e-14 V; t10–90 = τ·ln 9; τ̂ within 1 % |
| S4-2 | ADC: 12-bit 3.3 V mid-tread quantizer, SQNR sweep vs 6.02B + 1.76 dB, aliasing of 0.95 Hz fan ripple at Fs = 1 Hz, boxcar anti-alias | `s4_2_adc.m` | 0.244 µg/m³ and 1.0 ppm per LSB; SQNR within 0.06 dB; alias 0.05 Hz; AA −25.5 dB |
| S4-3 | Causal filters for CO₂ (sensor → ADC → filter): Hamming windowed-sinc FIR (M = 241) and first-order IIR in Direct Form II (transposed), block streaming zi → zf | `s4_3_filter.m` | Stopband 58 dB; group delay 120 samples = 20 min; streaming = batch; RMS error 8.4 → 3.1 ppm |
| S4-4 | Korean CAI (통합대기환경지수): QC flags, causal 1-h FIR, PM2.5/PM10 sub-indices, CAI = max, Schmitt hysteresis grades, JSON / CSV | `S4_4_cai_categorization.m` | Grade transitions 304 → 22 → 18 |
| S4-5 | AirKorea #131233 benchmark (OpenAPI JSON layout, offline mock) + hourly completeness rule + merged 4-channel Sensor Grid JSON + optional HTTP POST | `s4_5_benchmark_export.m` | PM2.5 r = 0.996, RMSE 2.5 µg/m³; grade agreement 87.5 %; 288 records |

## Outputs (`output/`)

`S4_1_sensor_step.png`, `S4_2_adc.png`, `S4_3_co2_filter.png`, `S4_4_fig1_pm25.png`, `S4_4_fig2_cai.png`,
`S4_4_fig3_grades.png`, `S4_5_benchmark.png`, `S4_4_telemetry.json/.csv`, `S4_sensor_grid.json`.
`data/airkorea_131233_mock.json` is the AirKorea-format reference file that S4-5 ingests.

## Notes

- The AirKorea reference is an **offline mock** in the real OpenAPI response layout. Its values are synthetic
  (seed 131233), so a live API key is not needed. To use real data, replace the file with an actual
  `getMsrstnAcctoRltmMesureDnsty` response for 송도. The parser stays the same.
- S4-4 calls `clear`/`close all` itself, so `run_S4` runs it in an isolated workspace.
  S4-1…S4-3 figures are saved to PNG before that.
- `tests/test_S4.m` runs S4-5 on `data/S4_4_telemetry_reference.csv`. S4-4 has its own asserts inside the script.
