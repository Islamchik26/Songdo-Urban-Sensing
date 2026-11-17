"""Independent source/formula check. Requires xlrd; does not execute MATLAB."""
from pathlib import Path
import hashlib
import json
import math
import xlrd

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data' / 'pressure_benchmark'


def reduce_pressure(p, height):
    return p * (1 - .0065 * height / 288.15) ** (-9.80665 * .0289644 / (8.3144598 * .0065))


def verify():
    source = json.loads((DATA / 'kma_monthly_pressure.json').read_text())
    raw = DATA / 'raw' / 'SYNM_202510.xls'
    assert hashlib.sha256(raw.read_bytes()).hexdigest() == source['raw_xls_sha256']
    sheet = xlrd.open_workbook(raw).sheet_by_name(source['source_sheet'])
    row = sheet.row_values(source['source_excel_row_1based'] - 1)
    assert str(row[0]) == source['station_id'] == '112'
    assert source['month'] == '2025-10' and source['aggregation'] == 'monthly_mean'
    for field in ['station_pressure_hpa', 'sea_level_pressure_hpa', 'air_temperature_c', 'relative_humidity_pct']:
        col = source['source_columns_1based'][field] - 1
        assert float(row[col]) == source[field]
    assert source['pressure_elevation_m'] == 70.2
    assert reduce_pressure(1000, 0) == 1000
    estimate = reduce_pressure(source['station_pressure_hpa'], source['pressure_elevation_m'])
    assert math.isclose(estimate, 1020.2628840368945, abs_tol=1e-10)
    # For this fixed-height/fixed-T0 formula, averaging commutes with reduction.
    assert math.isclose(reduce_pressure((1000+1010)/2, 70.2),
                        (reduce_pressure(1000, 70.2)+reduce_pressure(1010, 70.2))/2, abs_tol=1e-10)
    difference = estimate - source['sea_level_pressure_hpa']
    return {'status': 'PASS_SOURCE_AND_FORMULA_CHECK', 'evidence_type': 'Independent Python, not MATLAB execution',
            'station_id': '112', 'month': '2025-10', 'aggregation': 'monthly_mean',
            'station_pressure_mean_hpa': source['station_pressure_hpa'],
            'published_sea_level_pressure_mean_hpa': source['sea_level_pressure_hpa'],
            'barometer_elevation_m': 70.2, 'estimated_sea_level_pressure_mean_hpa': estimate,
            'signed_difference_hpa': difference, 'absolute_difference_hpa': abs(difference),
            'acceptance_threshold': None, 'exact_assignment_station_512_satisfied': False,
            'matlab_runtime_validated': False}


if __name__ == '__main__':
    result = verify()
    (ROOT / 'verification' / 'monthly_pressure_verification.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
