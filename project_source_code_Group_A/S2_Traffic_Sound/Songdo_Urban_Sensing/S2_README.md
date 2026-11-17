# Team S2 - Traffic Sound & Acoustic Fleet

Station `STATION_TECHNOPARK_ACOUSTIC` (37.3820 N, 126.6560 E, 9.0 m). Base MATLAB only, R2023b or later.
Everything lives in a new package `+songdo/+acoustic`, so it does not touch or depend on the shared
`+songdo/+core`, `+dsp` or `+io` code (except the optional HTTP POST in `run_S2('Post', true)`).

## Run

```matlab
cd matlab
run_S2;                    % S2-1 ... S2-5, figures, writes integration/S2_technopark_acoustic_telemetry.json
r = run_S2('Plot', false); % headless, returns r.Checks table
cd tests
test_S2;                   % 38 unit and numerical tests
```

Optional end-to-end delivery: start `python integration/mock_receiver.py`, then `run_S2('Post', true)`.

## Scenarios

| ID | What | Where |
|----|------|-------|
| S2-1 | 60 Hz notch (Q=30), 101-tap Hann-sinc FIR at 3.6 kHz, decimate by 6 (48 kHz -> 8 kHz) | `design_notch`, `design_fir_lowpass`, `AcousticChain` |
| S2-2 | A-weighting, bilinear 6th-order IIR (3 biquads) at 8 kHz | `design_a_weighting`, `sos_response`, `a_weight_db` |
| S2-3 | Rolling Leq 1 s, SPL 100 ms, Hann STFT 512/256, spectral centroid, HF ratio > 2.5 kHz | `level_series`, `stft_features` |
| S2-4 | Siren: eta = E[600,1000]/E[100,4000], Schmitt 0.55 / 0.35 | `schmitt_trigger`, `stft_features` |
| S2-5 | Sensor Grid JSON, quality flags, NoiseLab 65-68 dBA check | `export_s2_json`, `quality_flags` |

## Streaming

`AcousticChain.process(block)` keeps the notch, FIR and biquad states and the decimator phase between calls,
so it drops straight into a timer callback (`[pA, xDec] = app.Chain.process(x_block)`), with any block length.
`test_S2` proves block-wise output equals batch output and that resetting state per block does not.

## Things to know

* **Handbook typo (S2-2).** It lists "+1.2 dB at 1 kHz and -26.2 dB at 100 Hz". The IEC 61672 values are
  0.0 dB at 1 kHz, -19.1 dB at 100 Hz, +1.2 dB at 2 kHz and -26.2 dB at 63 Hz. The tests use the IEC values.
* **8 kHz limit.** A bilinear A-weighting at Fs = 8 kHz is within ~0.15 dB up to 2 kHz but droops above ~3 kHz
  (-1.4 dB at 3 kHz). The accuracy test covers 63 Hz - 2 kHz.
* **eta denominator.** The Handbook says "E_total"; here it is the 100 Hz - 4 kHz band so sub-100 Hz engine
  rumble cannot dilute the ratio. Change with `'TotalBandHz'` in `stft_features`.
* **Fixture is synthetic.** It is built to ~66-67 dBA overall, so the NoiseLab 65-68 dBA check validates
  the chain, not the real street. Swap in recorded WAV (`audioread`) and a measured sensitivity for a real run.
* **Level channels in JSON.** For `SPL_DBA_100MS` and `LEQ_1S_DBA`, `raw_value` is the flat dB SPL and
  `filtered_value` the A-weighted level; for `EVENT_SIREN_FLAG`, `raw_value` is eta and `filtered_value` the 0/1 flag.
