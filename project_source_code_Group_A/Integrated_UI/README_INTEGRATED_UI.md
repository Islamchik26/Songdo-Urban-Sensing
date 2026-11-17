# Team A — Integrated Engineering Instrument (S1–S5)

One MATLAB window that lets you **choose any station (S1…S5) or any scenario (Sx‑1…Sx‑5) and run it**, built on top of
the five members' midterm code **without modifying or copying it**.

## Launch

```matlab
cd Integrated_UI        % this folder
launch_songdo           % opens SongdoIntegratedApp
```

Base MATLAB R2023b or later (tested on R2025b). No toolboxes. The launcher adds every member folder to the path.

## What the window contains

| Tab | What it does |
|-----|--------------|
| **Task Runner** | Tree of 5 stations × 5 handbook scenarios. Select a task, press **Run**. The member's original entry point runs (`run_S1`, `run_S2`, `run_S3` + `run_KMA_observations`, `S4_4_cai_categorization.m`, `run_S5.m`). Its figures are shown embedded (or **Pop out** as interactive MATLAB figures), with a **handbook target vs measured** check table, the console lines for that scenario, and a JSON preview with schema validation. |
| **Live Instrument** | Handbook §5 oscilloscope for every station: 7‑stage signal‑chain strip, dual trace (raw vs causal filtered), Hann‑corrected one‑sided spectrum with Nyquist marker, live cutoff tuning (state kept), telemetry buffer table, **EXPORT JSON** (Sensor Grid §5.3 + CSV). Uses S2 `AcousticChain` and S3 `processBlock` directly; S1/S4/S5 filters are reproduced with the members' parameters because those were delivered as scripts. All block processing is causal with persistent `zi → zf` state. |
| **Verification** | Runs every member test suite (S1 `test_S1`, S2 `test_S2`, S3 `run_all_tests`, S4 embedded asserts), output‑based checks for S5 (which has no test file), Sensor Grid JSON schema for all five stations, station registry and Haversine checks. |
| **Station Map & Sensor Grid** | Clickable WGS84 map of the five stations, Haversine distance matrix, conformance table of every station's exported JSON. |
| **Console Log** | Everything every member script printed, with timestamps; can be saved. |

The header buttons **Run ALL 5 stations** (a unified end‑to‑end run) and **Run all verification suites** do everything in one click.

## How it maps to the midterm feedback

* *"An integrated App Designer or equivalent interactive instrument is unverified"*: this is that instrument (programmatic `uifigure`/`uiaxes`/`uitable`).
* *"A unified live run is unverified"*: **Run ALL 5 stations** plus the Live Instrument, with a common causal runtime (`+songdoui/LiveStream.m`).
* *"incomplete grid‑wide conformance evidence"*: `+songdoui/validateSensorGrid.m` checks all five exports against §5.3.

## Files

```
Integrated_UI/
  launch_songdo.m              entry point
  SongdoIntegratedApp.m        the app
  +songdoui/registry.m         stations, 25 scenarios, member entry points, figure mapping
  +songdoui/runStation.m       runs member code unchanged, captures console + figures
  +songdoui/runScriptIsolated.m  runs member scripts so their CLEAR/CLOSE ALL cannot affect the app
  +songdoui/s3Views.m          per-scenario S3 figures from the S3 member's API
  +songdoui/taskChecks.m       handbook target vs measured value per scenario
  +songdoui/LiveStream.m       common causal block-streaming runtime (12 channels)
  +songdoui/validateSensorGrid.m  Section 5.3 schema validator
  +songdoui/runVerification.m  all test suites + cross-station checks
  tests/test_integrated_backend.m, tests/test_integrated_app.m
  exports/                     live JSON/CSV exports (created on demand)
```

## Notes

* Running a station regenerates that member's own outputs in their folder, exactly as running their script by hand does.
* **S4‑1, S4‑2, S4‑3, S4‑5 were not in the midterm submission.** They appear greyed out as *not implemented*. When added, register the new figure names in `+songdoui/registry.m`.
* Adding a new scenario or station only requires editing `registry.m` (plus a `case` in `taskChecks.m` for numeric checks).
* Headless tests: `test_integrated_backend` (≈1 min) and `test_integrated_app(true)` (≈7 min, full run).
