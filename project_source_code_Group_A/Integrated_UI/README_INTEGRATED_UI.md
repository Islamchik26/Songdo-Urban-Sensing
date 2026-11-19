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
| **Task Runner** | Tree of 5 stations × 5 handbook scenarios. Select a task, press **Run**. The member's original entry point runs (`run_S1`, `run_S2`, `run_S3` + `run_KMA_observations`, `run_S4` (S4-1…S4-5, from `S4_Air_Quality_updated/`), `run_S5.m`). Its figures are shown embedded (or **Pop out** as interactive MATLAB figures), with a **handbook target vs measured** check table, the console lines for that scenario, and a JSON preview with schema validation. |
| **Live Instrument** | Handbook §5 oscilloscope for every station: 7‑stage signal‑chain strip, dual trace (raw vs causal filtered), Hann‑corrected one‑sided spectrum with Nyquist marker, live cutoff tuning (state kept), telemetry buffer table, **EXPORT JSON** (Sensor Grid §5.3 + CSV). Uses S2 `AcousticChain` and S3 `processBlock` directly; S1/S4/S5 filters are reproduced with the members' parameters because those were delivered as scripts. All block processing is causal with persistent `zi → zf` state. |
| **Verification** | Runs every member test suite (S1 `test_S1`, S2 `test_S2`, S3 `run_all_tests`, S4 `test_S4` + S4-4 embedded asserts + `run_S4` checks), output‑based checks for S5 (which has no test file), Sensor Grid JSON schema for all five stations, station registry and Haversine checks. |
| **Station Map & Sensor Grid** | Real basemap of Songdo (base-MATLAB `geoaxes`; Topographic by default, also streets, satellite, offline). The **Show** menu has three overviews (stations, latest readings with handbook colours, Sensor Grid JSON conformance) and one **site view per station**: S1 the 250 m² density area with IN/OUT gates, S2 noise contours estimated from the measured Leq (20 log r), S3 the latest wind vector plus every exported wind record, S4 a halo in the Korean CAI colour, S5 a staff gauge filled to the water level. The side panel shows the site details, station info, distances and a **history chart** of the station's key channel from its telemetry JSON (with alarm lines / CAI bands). Navigate with the arrow and zoom buttons, or drag and scroll. The handbook gives station points only, so each site overlay can be moved: in a site view press **Place site** and click the map (e.g. the walkway for the S1 counting area), rotate the S1 area with the arrow buttons, **Reset site** to go back. Positions are saved in `site_placement.json`; the handbook station points and JSON exports are not changed. Overlay sizes are in `registry.m` (`siteGeom`). Street/satellite/topographic tiles need internet. |
| **Console Log** | Everything every member script printed, with timestamps; can be saved. |

The header buttons **Run ALL 5 stations** (a unified end‑to‑end run) and **Run all verification suites** do everything in one click.
The interface opens in a dark theme; the **Light mode / Dark mode** header button switches it (e.g. for a projector), or call `app.setTheme('light')`. Member figures keep their original white background in both themes.

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
  +songdoui/latestReadings.m   latest value per channel from each station's JSON (map)
  +songdoui/channelSeries.m    channel time series from a station's JSON (map history chart)
  +songdoui/sitePlacement.m    load/save map site positions (site_placement.json)
  +songdoui/runVerification.m  all test suites + cross-station checks
  tests/test_integrated_backend.m, tests/test_integrated_app.m
  exports/                     live JSON/CSV exports (created on demand)
```

## Notes

* Running a station regenerates that member's own outputs in their folder, exactly as running their script by hand does.
* S4 now comes from `S4_Air_Quality_updated/S4_Air_Quality_Standalone` (all five scenarios). `run_S4` creates the S4‑1…S4‑3 figures before S4‑4's own `close all`; the UI keeps them by making figures hide instead of close while S4 runs.
* Adding a new scenario or station only requires editing `registry.m` (plus a `case` in `taskChecks.m` for numeric checks).
* Headless tests: `test_integrated_backend` (≈1 min) and `test_integrated_app(true)` (≈7 min, full run).
