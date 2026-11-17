# Separate monthly pressure consistency benchmark

The October 2025 KMA Monthly Meteorological Report gives Incheon ASOS 112 monthly mean station pressure 1011.8 hPa and sea-level pressure 1020.0 hPa. The same period's report lists barometer height Hb = 70.2 m (not ground height H = 69.0 m). This is an explicitly labeled alternative station, not Songdo AWS 631 or assignment station 512.

- `raw/SYNM_202510.xls`: original official workbook; selected sheet/row/columns and hash are in `kma_monthly_pressure.json`.
- `evidence/monthly_202510_pages_8_9_29.pdf`: unchanged relevant pages extracted from the official report. Page 8 contains station heights, page 9 defines Hb, and page 29 contains monthly observations. Original full-PDF hash and extraction details are alongside it.
- `kma_monthly_pressure.json`: source, POST parameters, monthly interval, values, elevation and limitations.
- `incheon_112_202510_monthly.csv`: a single monthly record, not an invented instantaneous observation.
- `extract_monthly.py`: re-extract the workbook row with Python `xlrd`. The MATLAB code does not require Python or xlrd.

From the project's MATLAB folder:

```matlab
setup_project
pressureReport = run_KMA_monthly_pressure_benchmark();
```

With the same fixed standard-atmosphere constants used in S3, the independent Python calculation gives estimated SLP 1020.262884 hPa versus published 1020.0 hPa, a signed/absolute difference of +0.262884/0.262884 hPa. This is descriptive only. No course acceptance tolerance is supplied; the result is not a pass/fail or exact-station compliance claim. New MATLAB execution is still pending.

The fixed standard-atmosphere factor is linear in station pressure, so averaging commutes with this specific fixed-factor equation. KMA's operational reduction may use different/time-varying conditions, and published monthly values are rounded. This single paired mean cannot validate instantaneous dynamics or weather noise removal.

Run `python verification/verify_monthly_pressure.py` from the project root to independently check the source values, XLS hash and formula. This test requires xlrd and does not execute MATLAB. The 361-row station 512 minute dataset remains separate, with station pressure still unavailable.

The additional `evidence/monthly_202510_aggregation_notes.pdf` retains the report's physical page 3: KST timing, daily means based on 03, 06, 09, 12, 15, 18, 21 and 24 h observations, and at least 80% data for daily/monthly statistics. These are published monthly aggregates, not an assumed mean of 10 Hz or continuous measurements.
