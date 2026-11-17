"""Independent local schema tests, no server or external traffic."""
import copy
import json
import unittest
from mock_receiver import CHANNEL_UNITS, load_strict, validate


def fixture():
    return {"schema_version":"1.0","generated_at":"2026-01-01T00:01:00.000Z",
            "station_id":"STATION_CENTRAL_PARK_WEATHER","latitude":37.3930,"longitude":126.6345,
            "records":[{"timestamp":"2026-01-01T00:00:00.000Z","channel":c,
                        "raw_value":1.0,"filtered_value":1.0,"unit":u,"quality_flag":"GOOD"}
                       for c,u in CHANNEL_UNITS.items()]}


class SchemaTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate(fixture()), [])
    def test_roundtrip(self):
        self.assertEqual(validate(load_strict(json.dumps(fixture()))), [])
    def test_wrong_station(self):
        f=fixture(); f['station_id']='512'; self.assertTrue(validate(f))
    def test_pressure_not_primary(self):
        f=fixture(); f['records'][0]['channel']='SEA_LEVEL_PRESSURE_HPA'; self.assertTrue(validate(f))
    def test_bad_unit(self):
        f=fixture(); f['records'][0]['unit']='K'; self.assertTrue(validate(f))
    def test_null_requires_flag(self):
        f=fixture(); f['records'][0]['raw_value']=None; self.assertTrue(validate(f))
        f['records'][0]['quality_flag']='DROPOUT'; self.assertFalse(validate(f))
    def test_bad_date(self):
        f=fixture(); f['generated_at']='2026-02-31T00:00:00.000Z'; self.assertTrue(validate(f))
    def test_duplicate(self):
        f=fixture(); f['records'].append(copy.deepcopy(f['records'][0])); self.assertTrue(validate(f))
    def test_missing_channel(self):
        f=fixture(); f['records'].pop(); self.assertTrue(validate(f))
    def test_bad_types(self):
        for value in ('37.0', True, None, {}, []):
            f=fixture(); f['latitude']=value; self.assertTrue(validate(f))
        f=fixture(); f['records'][0]['channel']=[]; self.assertTrue(validate(f))
    def test_huge_integer(self):
        f=fixture(); f['latitude']=10**400; self.assertTrue(validate(f))
        f=fixture(); f['records'][0]['raw_value']=10**400; self.assertTrue(validate(f))
    def test_nonfinite(self):
        for value in (float('nan'),float('inf')):
            f=fixture(); f['records'][0]['raw_value']=value; self.assertTrue(validate(f))
    def test_json_constants_and_duplicates(self):
        with self.assertRaises(ValueError): load_strict('{"x":NaN}')
        with self.assertRaises(ValueError): load_strict('{"x":1,"x":2}')


if __name__=='__main__': unittest.main(verbosity=2)
