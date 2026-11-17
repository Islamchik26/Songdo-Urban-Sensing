# S3 Micro Weather, native-cadence observation replay update

A source-grounded implementation of the five S3 scenarios for `STATION_CENTRAL_PARK_WEATHER` (37.3930 N, 126.6345 E, elevation 6.2 m). It is a local coursework prototype, not a production service or an official KMA integration. The other four stations exist only as source registry metadata.

## Run in MATLAB R2023b or later

Base MATLAB is sufficient. For a single logged validation command, follow `docs/MATLAB_ONLINE_QUICKSTART.md` and run `run_online_check`. For individual steps, open the `matlab` folder, then run:

```matlab
setup_project
observedReport = run_KMA_observations(); % Real KMA data, separate visible viewer
songdo.io.generate_fixtures();   % Seed-42 synthetic MAT and CSV fixtures
results = run_all_tests();       % Actual MATLAB assertions
report = run_S3();               % Noninteractive simulation and local exports
app = SongdoSensorApp();         % Optional separate live programmatic GUI
```

The previous v2 four-group test suite passed according to the user on Windows MATLAB R2026b at 2026-10-23 01:21 KST. This observation-replay update adds a fifth test group and has **not been run in MATLAB here**. The historical pass does not validate these additions. See `docs/VALIDATION_STATUS.md`.

To replay a local file:

```matlab
report = run_S3(fullfile(pwd,'replay_output'), '../data/replay/clean_plunge_reference.csv');
```

CSV columns are `time_s,AIR_TEMP_C,REL_HUMIDITY_PCT,WIND_U_MPS,WIND_V_MPS,PRESSURE_HPA` and optional `HUMIDITY_FAULT` (0/1). Rows must be uniformly spaced by 0.1 seconds. Missing sensor values may be NaN; missing time rows are not silently resampled. Replay and streaming enforce the same origin-based time grid. Sensor arithmetic is normalized to double; time_s must be double precision. Time is relative to the configured UTC minute anchor, not inferred from a filename. The bundled replay is synthetic.

## Real KMA observations, without synthetic replacement

Run `observedReport = run_KMA_observations();` for the separately bundled genuine station 512 observations (official name: Incheonyeonsu AWS), as selected by the user, at their native timestamps. See `docs/REAL_OBSERVATION_REPLAY.md` and the dataset provenance. This path neither interpolates observations into 10 Hz rows nor applies the 12-second PT100 compensation to sparse weather records. It retains the required simulated plunge test separately. The existing GUI's “View real KMA data” button opens the separate five-panel observation viewer and pauses any simulation. Native-cadence observations never enter the 10 Hz processor.

An optional, separate `run_KMA_monthly_pressure_benchmark()` compares an official October 2025 Incheon ASOS 112 paired monthly mean using its documented barometer elevation. It is descriptive alternative-station evidence, not the exact station-512 requirement. See `data/pressure_benchmark/README.md`.

## What is implemented

- S3-1: exact-ZOH PT100 simulation, handbook backward-difference compensation, and three causal lowpass poles; a defined clean 5 C plunge acceptance test.
- S3-2: 10 Hz u/v samples, trailing 100-sample vector means and direction, and trailing 30-sample scalar peak gust.
- S3-3: causal five-slot median, accepted-observation rate validation, and explicit GOOD/DROPOUT/SUSPECT_JUMP flags.
- S3-4: station-to-sea-level pressure correction, separate from the four registered channels.
- S3-5: complete one-minute aggregation, Sensor Grid JSON, a clearly named local KMA-style mock, and CSV.
- Simulation/replay GUI: persistent block state, fixed-spacing timer, rolling traces, Hann spectrum, quality/telemetry display, retained-state live cutoff changes, and local export. Hardware mode is explicitly unavailable.
- Common essentials: full five-station/20-channel metadata; Haversine, ADC quantization, symmetric FIR, ZOH stability, FFT normalization, hysteresis, and chunk-continuity tests.

The `mixed` simulation models an oversampled physical signal, PT100 dynamics, a causal first-order analog-conditioning approximation, 10 Hz sampling, a 16-bit midrise quantizer, and injected humidity corruption. The clean `temperature_plunge` case deliberately bypasses noise, ADC and analog conditioning to isolate the specified temperature-compensation delay test.

## Outputs

`run_S3` writes `S3_processed_samples.csv`, `S3_sensor_grid.json`, `S3_kma_style_mock.json`, `S3_minute_weather.csv`, `S3_run_report.json`, and, where graphics are available, `S3_results.png` into `outputs`.

Only complete, aligned 600-sample minute bins are exported. Numeric means exclude invalid observations and carry worst-in-minute quality flags. Wind direction is calculated from averaged components, never averaged as degrees. The Sensor Grid retains exactly the four source-registered channels; pressure appears in the separate mock/CSV records.

Validate an actual MATLAB export without opening a port:

```sh
python integration/mock_receiver.py --validate outputs/S3_sensor_grid.json
python -m unittest discover -s integration -p 'test_*.py' -v
```

An optional loopback-only receiver is provided for a manual local HTTP demonstration:

```sh
python integration/mock_receiver.py --serve
```

It is not started by the app or runner. A successful mock validation proves this project's schema only, not official KMA acceptance. No network submission is performed automatically.

## Before submission

1. Run the MATLAB tests and GUI lifecycle checklist in `matlab/apps/AppDesigner_Build_Guide.md`.
2. Save real MATLAB run outputs and replace provisional validation notes with actual results.
3. Run the new native-cadence observation replay and check its provenance. The station number now matches the user-selected 512, while the paired-pressure benchmark remains open; absent station pressure is not fabricated.
4. Keep the submission scope labeled S3 only. Registry metadata is not an implementation of S1/S2/S4/S5 scenarios.
5. Prepare the course's separate proposal/report and member-participation video. This code package does not claim those are complete.

See `docs/V2_HARDENING.md` for concrete corrections and new failure-case tests.

Read `docs/ASSUMPTIONS.md`, `docs/MATH_AND_DESIGN.md`, and `docs/REQUIREMENTS_TRACEABILITY.md` for definitions, tradeoffs and open requirements.
