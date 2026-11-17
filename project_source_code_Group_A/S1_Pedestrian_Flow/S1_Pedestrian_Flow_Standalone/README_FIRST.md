# S1 Pedestrian Flow — MATLAB project

This is a standalone MATLAB implementation for the S1 Pedestrian Density & Flow assignment. It uses **synthetic demonstration data**, not live measurements from Songdo Convensia.

## Run the project

1. Extract the ZIP file.
2. In MATLAB R2023b or later, set the Current Folder to the extracted `S1_Pedestrian_Flow_Standalone` folder (or `cd` into it).
3. Run:

   ```matlab
   result = run_S1();
   ```

4. Run the test suite:

   ```matlab
   run('tests/test_S1.m')
   ```

The script generates four figures and saves these files to `output/`:

- `S1_1_PIR_Response.png`
- `S1_2_Filter_ADC.png`
- `S1_3_Event_Detection.png`
- `S1_4_Density_Surge.png`
- `S1_results.mat`
- `S1_telemetry.csv`
- `S1_telemetry.json`

## What changed in the plotting logic

- **S1-1 PIR response:** displays the first six seconds instead of squeezing a sub-four-second transient into a ten-minute axis. The 10%, 90%, and settling-time references make the sensor time constant visible.
- **S1-2 filtering and ADC:** pre-rolls the causal filter from the initial signal level to prevent an artificial startup jump, uses a three-second window to compare raw, filtered, and quantized signals, then a separate 250 ms zoom for quantization error. This prevents 120,000 samples from painting the error subplot into a solid block. Quantized points use sparse markers because the ADC step is far smaller than the full voltage scale.
- **S1-3 event detection:** separates the full ten-minute cumulative entry/exit history from an eight-second pulse detail. Full-run totals appear on the full-run panel, not on a short zoom, so numbers and displayed time range agree.
- **S1-4 density and surge:** uses a bursty ten-minute synthetic crowd schedule with periods of inflow and outflow. The rate is calculated from a causal two-second moving average before differentiation, avoiding large one-sample spikes caused by differentiating a count staircase. A third panel shows when the alarm is active.

## Important interpretation of the rate threshold

The assignment's density threshold is 2.5 people/m², and the specified density-rate threshold is 0.3 people/(m²·s). With one accepted event per sensor pulse and a 250 m² monitored area, the generated event stream may not reach the rate threshold. The code deliberately **does not silently change the assignment threshold**. The density condition can still trigger the surge alarm. The S1-4 plot prints the measured rate range and notes when the rate threshold is not reached.

## Design assumptions retained

- Sampling rate: 200 Hz
- PIR sensor time constant: 0.8 s; gain: 2.5
- Pressure low-pass filter: causal second-order Butterworth, 40 Hz cutoff
- ADC: 12-bit over 0–3.3 V
- Event detection: ±0.75 V threshold, re-arm within ±0.20 V, 15-sample minimum duration
- Density area: 250 m²
- Surge thresholds: 2.5 people/m² and 0.3 people/(m²·s)

The filtering remains causal; no `filtfilt` is used. Check the assignment handbook with your instructor if any simulation parameter or interpretation differs from the required scenario.
