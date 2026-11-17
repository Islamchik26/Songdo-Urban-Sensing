"""Independent bundled-data checks. This does NOT execute or validate MATLAB."""
from pathlib import Path
from datetime import datetime, timedelta
import csv
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data' / 'observations'


def verify():
    metadata = json.loads((DATA / 'kma_provenance.json').read_text())
    with (DATA / 'kma_observations.csv').open(newline='') as handle:
        rows = list(csv.DictReader(handle))
    assert metadata['station_id'] == '512'
    assert metadata['network'] == 'KMA AWS (not ASOS)'
    assert len(rows) == metadata['sample_count'] == 361
    times = [datetime.fromisoformat(r['TIMESTAMP_UTC'].replace('Z', '+00:00')) for r in rows]
    assert all(b - a == timedelta(seconds=60) for a, b in zip(times, times[1:]))
    assert rows[0]['TIMESTAMP_UTC'] == metadata['start_utc']
    assert rows[-1]['TIMESTAMP_UTC'] == metadata['end_utc']
    source_rows = {}
    duplicate_count = 0
    for relative, expected_hash in metadata['raw_sha256'].items():
        raw = (DATA / relative).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == expected_hash, relative
        source = raw.decode('euc-kr')
        assert '인천연수 512' in source
        for line in source.splitlines():
            match = re.search(r'stn_tm_select\(\d+,(\d{12})\)', line)
            if not match:
                continue
            cells = [html.unescape(re.sub('<[^>]*>', '', value)).strip()
                     for value in re.findall(r'<td[^>]*>(.*?)</td>', line, re.I)]
            assert len(cells) == 16
            key = match[1]
            if key in source_rows:
                assert source_rows[key] == cells
                duplicate_count += 1
            source_rows[key] = cells
    assert len(source_rows) == len(rows)
    assert duplicate_count == 5
    calm_count = 0
    for row in rows:
        assert row['STATION_ID'] == '512'
        local = datetime.fromisoformat(row['TIMESTAMP_ORIGINAL_KST'])
        assert local.utcoffset() == timedelta(hours=9)
        utc = datetime.fromisoformat(row['TIMESTAMP_UTC'].replace('Z', '+00:00'))
        assert local == utc
        original = source_rows[local.strftime('%Y%m%d%H%M')]
        for field, index in [('AIR_TEMP_C', 7), ('REL_HUMIDITY_PCT', 14),
                             ('WIND_SPEED_MPS', 10), ('SEA_LEVEL_PRESSURE_HPA', 15),
                             ('WIND_FROM_DEG_RAW', 8), ('WIND_10MIN_FROM_DEG_RAW', 11),
                             ('WIND_10MIN_SPEED_MPS_RAW', 13)]:
            assert float(row[field]) == float(original[index]), (field, row)
        assert row['STATION_PRESSURE_HPA'] == ''
        if float(row['WIND_SPEED_MPS']) == 0:
            assert row['WIND_FROM_DEG'] == ''
            calm_count += 1
        else:
            assert float(row['WIND_FROM_DEG']) == float(original[8])
    assert calm_count == 107
    assert metadata.get('pressure_elevation_m') is None
    return {
        'evidence_type': 'Python data/provenance verification only; MATLAB not executed',
        'status': 'PASS', 'station_id': '512', 'rows': len(rows),
        'interval_seconds': 60, 'raw_files_hash_verified': len(metadata['raw_sha256']),
        'identical_overlap_rows_removed': duplicate_count,
        'calm_direction_rows_missing_by_design': calm_count,
        'source_station_pressure_count': 0,
        'raw_to_normalized_values_verified': True,
        'matlab_runtime_validated': False,
        'pressure_benchmark_completed': False,
    }


if __name__ == '__main__':
    report = verify()
    target = ROOT / 'verification' / 'kma_dataset_verification.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
