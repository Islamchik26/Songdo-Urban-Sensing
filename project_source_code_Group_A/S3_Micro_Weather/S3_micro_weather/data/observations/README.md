# Official Incheonyeonsu AWS 512 minute observations

The user selected station 512. Its official name is Incheonyeonsu (인천연수), KMA AWS, not Songdo ASOS. These are newly downloaded station 512 records, not relabeled station 631 data. The virtual Central Park S3 station and its 6.2 m elevation remain separate.

## Dataset

- 361 original one-minute observations, 2025-10-01 17:00–23:00 KST inclusive (08:00–14:00 UTC).
- Six original station 512 responses retained byte-for-byte in `raw/`. Each header was verified as 인천연수 512.
- Temperature, RH, one-minute mean wind speed, numeric meteorological FROM direction and sea-level pressure.
- Station pressure is unavailable and remains blank. This file alone cannot validate sea-level pressure reduction.
- 107 calm observations have undefined normalized wind direction; the original direction remains in `WIND_FROM_DEG_RAW`.
- Five identical overlapping hour-boundary rows removed; KST converted to UTC. No interpolation, synthetic noise, upsampling or fabricated 10 Hz observations.
- Ground elevation 8.13 m comes from official metadata; it is not a verified barometer elevation. Date-specific relocation history is not established.

The default viewer reads `kma_observations.csv` and `kma_provenance.json`. The sidecar records source URLs, station identity, units, processing, raw hashes, attribution and limitations. Public-table QC flags are not available; missing flags do not certify instrument quality.

## Reproduce and verify

`download_incheonyeonsu.py` downloads the six original tables, reusing existing files. `normalize_incheonyeonsu.py` extracts them into the default CSV/JSON names. Both use the Python standard library. Exact per-response receipt timestamps were not logged, so metadata records the actual retrieval date, 2026-10-22, without invented precision.

From the project root, run `python verification/verify_kma_dataset.py`. It checks all six raw hashes, station 512 headers, exact raw-to-normalized values, timestamp conversion, 60-second cadence, missing station pressure and 107 calm directions. Its result is `verification/kma_dataset_verification.json`. This does not execute MATLAB.

## Official sources

- Minute table: https://www.weather.go.kr/cgi-bin/aws/nph-aws_txt_min_cal_test?202510011800&0&MINDB_01M&512&m&1
- Station metadata: https://data.kma.go.kr/tmeta/stn/selectStnDetail.do?isSelectStn=Y&pgmNo=82&stdStnNo=512
- Wind direction convention FAQ: https://bd.kma.go.kr/contest/faq_view.do (Q15–16)
- Copyright policy: https://data.kma.go.kr/cmmn/static/staticPage.do?page=pageCr

Attribution: Korea Meteorological Administration, Incheonyeonsu AWS 512 observations, 2025-10-01. The legacy tables do not display a dataset-specific license badge; no specific KOGL license grant is asserted.
