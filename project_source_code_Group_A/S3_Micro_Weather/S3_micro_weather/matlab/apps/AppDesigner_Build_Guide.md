# S3 Micro Weather: MATLAB app guide

## Status and scope

`SongdoSensorApp.m` is a programmatic MATLAB app, not a `.mlapp` binary. It uses `uifigure`, `uigridlayout`, `uiaxes`, `uitable`, and `timer`; Base MATLAB R2023b or later is the target. The assignment's R2024a target is also appropriate. No optional toolbox, Arduino support package, or network connection is required.

The app implements local **simulation and CSV replay for S3 only**. Hardware mode is displayed but cannot start because no device adapter exists. Synthetic/replayed data is never described as live hardware acquisition or verified KMA observations. Pressure is a local diagnostic, not an invented fifth primary channel in the source registry.

**Verification limit:** MATLAB and Octave were not installed in the build environment. Source/API integration and static control-flow checks were performed; MATLAB Code Analyzer, GUI launch, timer behavior, visual layout, and interactive lifecycle tests remain runtime gates. No screenshot or live demo is claimed. Do not mark those gates passed until running the app in MATLAB.

## Launch

From the project folder, open MATLAB and run:

```matlab
cd matlab
setup_project
results = run_all_tests();
app = SongdoSensorApp();
```

`run_all_tests` exercises the shared processing and IO, not the graphical lifecycle. If a MATLAB test fails, address it before claiming a successful app demonstration.

The constructor accepts a complete configuration or a partial override struct. Unspecified fields come from `songdo.core.defaultConfig`:

```matlab
cfg = songdo.core.defaultConfig();
cfg.scenario = 'temperature_plunge'; % clean tracking-delay scenario
cfg.durationSeconds = 180;
cfg.tempLowpassHz = 0.2;
app = SongdoSensorApp(cfg);

% Short lifecycle rehearsal, without enough data for minute export:
shortApp = SongdoSensorApp(struct('durationSeconds', 12));
```

Use `delete(app)` to close an app from the command line. Closing its window follows the same cleanup path. Keep the app handle if you want to use its public methods. A read-only snapshot is available for acceptance checks:

```matlab
[playedInput, processedOutput, currentCfg] = app.getResults();
% After a live retune, inspect processedOutput.TEMP_CUTOFF_HZ.
% currentCfg describes the current setting, not the whole session history.
```


## Controls and demo flow

1. **Station:** locked to Central Park S3, `STATION_CENTRAL_PARK_WEATHER`, 37.3930 N, 126.6345 E, 6.2 m. Other stations are not implemented by this app.
2. **Mode:** select Simulation, CSV replay, or Hardware (unavailable). A mode change clears the previous in-memory session. In Simulation, Start generates the configured deterministic fixture. In Replay, Choose CSV validates the file before replacing an existing session; Start also offers the chooser when no file is loaded.
3. **Fs:** locked at 10 Hz to preserve the required wind sampling rate. Non-10-Hz constructor configurations are rejected rather than silently resampled.
4. **Pole fc:** temperature lowpass cutoff per repeated first-order pole. While Running, a valid change applies at the next block boundary without restarting the timer, discarding rows, or reinitializing filter/window state. A physical retuning transient is expected; bumpless output and real-time performance are not guaranteed. The core records `TEMP_CUTOFF_HZ` on every processed row. A stopped/paused edit instead clears processed results and state for a fresh fixed-setting comparison. Invalid values are rejected before changing the active config.
5. **UTC base:** `YYYY-MM-DDTHH:MM:00.000Z`, at a whole UTC minute. Export timestamps are this anchor plus input `time_s`. Replay does not recover, verify, or infer observation UTC from its CSV. Set the correct anchor if you know it. A changed anchor clears old outputs.
6. **Channel:** switch among the four primary channels, plus the local pressure diagnostic. Channel changes are allowed during playback and do not reset processing.
7. **Start / Resume:** begin playback, or continue from the exact paused row with filter and wind-window state intact. At EOF, Run again resets processing and replays the same input from row one. Repeated Start calls do not create extra timers.
8. **Stop:** pause and delete the current timer, preserving data and processor state. Repeated Stop is harmless.
9. **Reset:** stop playback, clear results and filters/windows, and retain the selected source for a fresh run. It also works while playing.
10. **Export local files:** available while stopped after at least 600 processed samples. Export still requires a full aligned minute; sample count alone is insufficient if replay starts partway through a minute. Incomplete leading/trailing bins are omitted by the IO layer, or it reports that no complete bin exists. No server is contacted.

For a default demonstration, Start in Simulation, switch through the channels, pause after at least the first full minute, export, resume to EOF, and close the window. Data processing time is displayed on the screen. A default run contains 180 seconds of input; elapsed wall time can be longer.

## CSV replay

Required numeric column names:

```text
time_s,AIR_TEMP_C,REL_HUMIDITY_PCT,WIND_U_MPS,WIND_V_MPS,PRESSURE_HPA
```

- `time_s` is nonnegative, finite, strictly increasing, and regularly spaced by 0.1 s. No automatic resampling occurs.
- `HUMIDITY_FAULT` is optional and contains 0/1. An explicit fault can identify a salt-mist endpoint transient. Otherwise a physically valid 0% or 100% humidity is not automatically a dropout.
- Nonfinite sensor observations remain observations with quality handling; they do not justify fabricating values in the source data.
- Additional truth columns may be retained by the processor but are not used as a substitute for acquired input.
- Choose Cancel to keep the existing input, processed results, and mode. A malformed replacement CSV likewise leaves the old session intact.

The same adapter can be invoked through the app without opening a chooser:

```matlab
app.chooseReplay(fullfile('..', 'data', 'fixtures', 'S3_centralpark_weather.csv'));
app.start();
```

Use the actual generated fixture path from your checkout. Provenance is explicitly displayed as local CSV replay, even when the filename resembles an official dataset.

## What the plots mean

- **Raw and processed scopes:** last 60 seconds (at most 600 rows) of the selected channel, on input-time axes. Temperature compares measured sensor output with lag-compensated, three-pole-smoothed output. Humidity shows the causal median/rate-validated result.
- **Wind speed:** instantaneous scalar speed versus the magnitude of the trailing vector mean. The table also shows the three-second maximum gust. The ten-second-window completion state is visible during startup and missing-data windows.
- **Wind direction:** north-referenced vector bearing from the supplied `atan2d(mean(u), mean(v))`, not an assumed meteorological wind-from conversion. Calm direction is undefined. Its local table state says `CALM / UNDEFINED (display)`, not a misleading GOOD value. That display label is not added to the export quality schema.
- **Pressure:** station pressure versus the calculated sea-level reduction. This is a correction, not a causal lowpass filter.
- **Spectrum:** shared `songdo.dsp.oneSidedSpectrum`, periodic Hann window with coherent-gain normalization, interior positive bins doubled and DC/Nyquist handled separately. This is amplitude, not power spectral density. The app removes each trace's mean to reveal dynamic content, uses its latest contiguous finite tail, requires at least 16 samples, and never interpolates across missing samples. The two traces may therefore use different sample counts/frequency resolutions after gaps. Off-bin tones can still leak or scallop.
- **Refresh rate:** scopes and latest-sample table every block; spectrum on the first and every fourth block, plus channel switches and EOF. At the default ten-sample block, this is roughly once per second for scopes and once per four seconds for the spectrum.
- **Circular spectrum caveat:** no scalar FFT of wrapped wind-direction degrees is shown; wrap discontinuities would create misleading frequency content. Use wind speed for a scalar wind spectrum.

The cutoff field is **per pole**, not the three-pole cascade's total −3 dB frequency. With `p = exp(-2*pi*fc/Fs)`, the cascade is `[(1-p)/(1-p*z^-1)]^3`. At `Fs = 10 Hz` and per-pole `fc = 0.2 Hz`, the discrete cascade's −3 dB frequency is about **0.10205 Hz**. This does not change the specified three-pole architecture.

## Architecture and lifecycle

The UI delegates all signal processing to the shared core:

```matlab
state = songdo.core.initState(cfg);
[processedBlock, state] = songdo.core.processBlock(inputBlock, state, cfg);
```

State persists between blocks, across pause/resume, and during running cutoff updates. No `filtfilt` or future-window smoothing is used. A separate rolling plot buffer avoids redrawing the full session; full processed rows are retained in memory for export. Replay input is loaded into memory, so this is a finite-file demonstrator, not a bounded-memory indefinite logger.

One owned timer uses `ExecutionMode = 'fixedSpacing'` and `Period = blockSamples/fsHz`. MATLAB fixed-spacing timers wait the period after the preceding callback finishes, so wall-clock playback is not a hard-real-time acquisition guarantee and can drift behind source time. Exports use source time, never callback arrival time. See the [MathWorks timer reference](https://www.mathworks.com/help/matlab/ref/timer.html).

Lifecycle safeguards in the code:

- Repeated Start is ignored while running; owned timers are deleted before replacement.
- Callbacks verify the timer identity so an obsolete timer cannot process the next block.
- Processing advances the input cursor only after the core succeeds.
- Stop, reset, EOF, processing/timer error, and close all clean up the owned timer.
- UI controls prevent source/UTC edits during playback and guard modal chooser operations. The cutoff alone supports live tuning; a candidate configuration is validated before committing, and the next block uses it with existing causal state.
- The final short block is processed without inventing extra samples.
- EOF refreshes the spectrum and enables a clean rerun.
- Errors surface in the app and retain already-completed results; a subsequent Start from Error resets the processor instead of continuing uncertain state.
- Closing the app does not delete timers owned by other MATLAB applications.

The exported files are `S3_sensor_grid.json`, `S3_kma_style_mock.json`, and `S3_minute_weather.csv`. The KMA-shaped outputs are project-defined mocks, not proof of official ASOS conformance or a successful KMA benchmark. Re-exporting to the same folder replaces those same filenames. Export uses only rows already processed; no unplayed samples are included.

## MATLAB runtime acceptance checklist

Record actual results and screenshots only after running these checks in MATLAB:

- [ ] `checkcode('apps/SongdoSensorApp.m')` completes; review each diagnostic.
- [ ] `run_all_tests()` passes in the target MATLAB release.
- [ ] App opens with visible readable controls and all axes/table at the target display size.
- [ ] Simulation advances one block at a time, displays quality changes, and plots every channel.
- [ ] Start twice does not speed up the source cursor or leave two active app timers.
- [ ] Stop twice is safe; Resume continues rather than restarts.
- [ ] Reset during playback stops the timer and clears all old results; Start begins at the first row.
- [ ] EOF handles a duration not divisible by block size; Run again is a fresh deterministic run.
- [ ] Replay chooser Cancel preserves the previous session. Invalid CSV replacement preserves it too.
- [ ] An irregular/missing-column CSV is rejected clearly; a valid fixture replays.
- [ ] Cutoff rejects 0, negative, Nyquist, NaN, and invalid text; valid stopped edits clear old outputs.
- [ ] During Running, cutoff changes apply to the next block without cursor reset, duplicate/missing rows, timer replacement, or state reset. Inspect the recorded `TEMP_CUTOFF_HZ` history and expected retuning transient; confirm other controls stay locked.
- [ ] UTC anchor rejects invalid dates, offsets, and non-whole-minute times; valid edits clear outputs.
- [ ] Hardware mode cannot Start and claims no connected device.
- [ ] Export is disabled before 600 rows; replay with no complete aligned minute reports the precise limitation.
- [ ] Export after a complete minute produces local files passing shared schema tests; cancelling writes nothing.
- [ ] Closing during playback leaves no timer from that app; another app's timer remains untouched.
- [ ] The four registered channels export correctly; local pressure remains distinct from the primary registry.
- [ ] Mean-removed spectrum scaling, dropout tails, calm direction, and control resizing are visually checked.

A quick isolated lifecycle rehearsal (not a substitute for the full checklist):

```matlab
before = numel(timerfindall('Tag', 'SongdoSensorAppTimer'));
a = SongdoSensorApp(struct('durationSeconds', 12));
a.start(); a.start();
pause(2.5);
a.stop(); a.stop();
a.start();
pause(1.2);
a.reset();
a.start();
pause(1.2);
delete(a);
assert(numel(timerfindall('Tag', 'SongdoSensorAppTimer')) == before);
```

Run that check while no other app instance is being started or stopped. Do not use `delete(timerfindall)` indiscriminately: unrelated apps can own timers.

## Not yet implemented

- Hardware input adapters or real-time acquisition guarantees.
- Runtime verification of the live-retuning implementation. Retained-state next-block updates are implemented, but the source rubric's “live tuning without dropouts” must still be demonstrated in MATLAB; no measured continuity/performance result is claimed.
- Verified real KMA observations, station-identity confirmation, or an official KMA schema/benchmark.
- A binary `.mlapp` and runtime-captured screenshots.
- Other teams' scenario implementations.

The programmatic source can be maintained directly. If a `.mlapp` is later required, recreate the component layout in App Designer and keep the same shared core/IO functions and lifecycle contract; do not duplicate processing equations in callbacks. The current assignment material allows the programmatic app.
