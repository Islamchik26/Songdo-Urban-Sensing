#!/usr/bin/env python3
"""Generate independent deterministic S3 CSV contract oracles.

This is not MATLAB execution. The generated expected values let an actual
MATLAB run be compared later, including arbitrary block sizes and a retune.
No third-party packages are required. Writes only under this script's folder.
"""
import csv
import json
import math
from collections import deque
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent / "golden"
FS, DT = 10.0, 0.1
FIELDS = ["time_s", "AIR_TEMP_C", "REL_HUMIDITY_PCT", "WIND_U_MPS", "WIND_V_MPS", "PRESSURE_HPA", "HUMIDITY_FAULT"]
OUTPUT = FIELDS + ["TEMP_CUTOFF_HZ", "AIR_TEMP_COMP_C", "AIR_TEMP_FILTERED_C", "TEMP_QUALITY", "REL_HUMIDITY_FILTERED_PCT", "HUMIDITY_QUALITY", "WIND_SPEED_MPS", "WIND_MEAN_SPEED_MPS", "WIND_MEAN_DIR_DEG", "WIND_GUST_MPS", "WIND_QUALITY", "WIND_WINDOW_COMPLETE", "SEA_LEVEL_PRESSURE_HPA", "PRESSURE_QUALITY"]


def mean(values):
    values = [v for v in values if math.isfinite(v)]
    return math.fsum(v / len(values) for v in values) if values else math.nan


def quality(value, lower, upper):
    if not math.isfinite(value):
        return "DROPOUT"
    return "GOOD" if lower <= value <= upper else "OUT_OF_RANGE"


def make_input():
    data, temperature = [], 25.0
    a = math.exp(-DT / 12.0)
    for i in range(1201):
        t = i / FS
        if i:
            previous_truth = 25 if (i - 1) < 300 else 20
            temperature = a * temperature + (1 - a) * previous_truth
        raw_temp = temperature
        if i in (0, 1, 313, 314, 315, 600, 601, 602):
            raw_temp = math.nan
        elif i == 401:
            raw_temp = -100.0
        humidity = 50.0 if i < 150 else (70.0 if i < 300 else 50.0)
        if 800 <= i < 860:
            humidity = math.nan
        elif i == 900:
            humidity = -1.0
        elif i >= 1000:
            humidity = 55.0
        fault = i in (450, 451, 650)
        if fault:
            humidity = 100.0 if i == 650 else 0.0
        angle = math.radians(359 if i % 2 == 0 else 1)
        u, v = math.sin(angle), math.cos(angle)
        if i == 150:
            u, v = 9.0, 0.0
        if i in (200, 201, 600):
            u = math.nan
        if i == 300:
            u = v = float.fromhex("0x1.fffffffffffffp+1023")
        if i >= 900:
            u = v = 0.0
        pressure = 1012.0
        if i in (0, 500, 601):
            pressure = math.nan
        elif i == 850:
            pressure = 100.0
        data.append(dict(zip(FIELDS, [t, raw_temp, humidity, u, v, pressure, int(fault)])))
    return data


def process(data, retune=False):
    result = []
    previous_temp = previous_temp_time = math.nan
    stages = None
    humidity_buffer, wind_buffer = deque(maxlen=5), deque(maxlen=100)
    accepted_rh = accepted_time = math.nan
    pressure_factor = (1 - .0065 * 6.2 / 288.15) ** (-9.80665 * .0289644 / (8.3144598 * .0065))
    for source in data:
        row, t = dict(source), source["time_s"]
        cutoff = .3 if retune and t >= 60 else .2
        pole = math.exp(-2 * math.pi * cutoff / FS)
        row["TEMP_CUTOFF_HZ"] = cutoff
        temp = source["AIR_TEMP_C"]
        tq = quality(temp, -80, 80)
        comp = math.nan
        if tq == "GOOD":
            if stages is None:
                comp, stages = temp, [temp] * 3
            else:
                comp = temp + 12 / (t - previous_temp_time) * (temp - previous_temp)
                stage = comp
                for k in range(3):
                    stages[k] = pole * stages[k] + (1 - pole) * stage
                    stage = stages[k]
            previous_temp, previous_temp_time = temp, t
        row.update(AIR_TEMP_COMP_C=comp, AIR_TEMP_FILTERED_C=math.nan if stages is None else stages[-1], TEMP_QUALITY=tq)

        raw_rh = source["REL_HUMIDITY_PCT"]
        hq = "DROPOUT" if source["HUMIDITY_FAULT"] else quality(raw_rh, 0, 100)
        humidity_buffer.append(raw_rh if hq == "GOOD" else math.nan)
        if hq == "GOOD":
            candidate = statistics.median(v for v in humidity_buffer if math.isfinite(v))
            if not math.isfinite(accepted_rh) or abs(candidate - accepted_rh) <= 2 * (t - accepted_time) + 1e-10:
                accepted_rh, accepted_time = candidate, t
            else:
                hq = "SUSPECT_JUMP"
        row.update(REL_HUMIDITY_FILTERED_PCT=accepted_rh, HUMIDITY_QUALITY=hq)

        u, v = source["WIND_U_MPS"], source["WIND_V_MPS"]
        scalar = math.hypot(u, v)
        good = math.isfinite(u) and math.isfinite(v) and math.isfinite(scalar)
        wind_buffer.append((u, v, scalar) if good else (math.nan, math.nan, math.nan))
        valid = [sample for sample in wind_buffer if math.isfinite(sample[2])]
        mean_u, mean_v = mean([sample[0] for sample in valid]), mean([sample[1] for sample in valid])
        mean_speed = math.hypot(mean_u, mean_v)
        direction = math.degrees(math.atan2(mean_u, mean_v)) % 360 if mean_speed > 1e-6 else math.nan
        gust_valid = [sample[2] for sample in list(wind_buffer)[-30:] if math.isfinite(sample[2])]
        row.update(WIND_SPEED_MPS=scalar if good else math.nan, WIND_MEAN_SPEED_MPS=mean_speed,
                   WIND_MEAN_DIR_DEG=direction, WIND_GUST_MPS=max(gust_valid) if gust_valid else math.nan,
                   WIND_QUALITY="GOOD" if len(valid) == len(wind_buffer) else "DROPOUT",
                   WIND_WINDOW_COMPLETE=int(len(valid) == len(wind_buffer) == 100))
        raw_p = source["PRESSURE_HPA"]
        pq = quality(raw_p, 300, 1100)
        row.update(SEA_LEVEL_PRESSURE_HPA=raw_p * pressure_factor if pq == "GOOD" else math.nan, PRESSURE_QUALITY=pq)
        result.append(row)
    return result


def worst(flags):
    order = ["GOOD", "SUSPECT_JUMP", "DROPOUT", "OUT_OF_RANGE"]
    return max(flags, key=order.index)


def minute_summary(data, output):
    result = []
    for minute in range(len(data) // 600):
        src = data[minute * 600:(minute + 1) * 600]
        out = output[minute * 600:(minute + 1) * 600]
        good_temp = [r for r in out if r["TEMP_QUALITY"] == "GOOD"]
        good_rh = [r for r in out if r["HUMIDITY_QUALITY"] == "GOOD"]
        valid_wind = [r for r in src if math.isfinite(r["WIND_U_MPS"]) and math.isfinite(r["WIND_V_MPS"]) and math.isfinite(math.hypot(r["WIND_U_MPS"], r["WIND_V_MPS"]))]
        valid_pressure = [r for r in out if r["PRESSURE_QUALITY"] == "GOOD"]
        mu = mean([r["WIND_U_MPS"] for r in valid_wind])
        mv = mean([r["WIND_V_MPS"] for r in valid_wind])
        speed = math.hypot(mu, mv)
        direction = math.degrees(math.atan2(mu, mv)) % 360 if speed > 1e-6 else math.nan
        row = {
            "timestamp": f"2026-01-01T00:{minute:02d}:00.000Z",
            "ta_c": mean([r["AIR_TEMP_FILTERED_C"] for r in good_temp]),
            "rh_pct": mean([r["REL_HUMIDITY_FILTERED_PCT"] for r in good_rh]),
            "ws_mps": speed, "wd_deg": direction,
            "gust3s_mps": max((r["WIND_GUST_MPS"] for r in out if math.isfinite(r["WIND_GUST_MPS"])), default=math.nan),
            "station_pressure_hpa": mean([r["PRESSURE_HPA"] for r in valid_pressure]),
            "sea_level_pressure_hpa": mean([r["SEA_LEVEL_PRESSURE_HPA"] for r in valid_pressure]),
            "sample_count": len(src), "temperature_good_count": len(good_temp),
            "humidity_good_count": len(good_rh), "wind_valid_count": len(valid_wind), "pressure_good_count": len(valid_pressure),
            "temperature_quality": worst([r["TEMP_QUALITY"] for r in out]),
            "humidity_quality": worst([r["HUMIDITY_QUALITY"] for r in out]),
            "wind_quality": worst([r["WIND_QUALITY"] for r in out]),
            "pressure_quality": worst([r["PRESSURE_QUALITY"] for r in out]),
        }
        result.append(row)
    return result


def write_csv(path, rows, fields):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows({key: "NaN" if isinstance(value, float) and math.isnan(value) else value for key, value in row.items()} for row in rows)


def json_finite(value):
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {k: json_finite(v) for k, v in value.items()}
    if isinstance(value, list):
        return [json_finite(v) for v in value]
    return value


if __name__ == "__main__":
    ROOT.mkdir(exist_ok=True)
    data = make_input()
    write_csv(ROOT / "adversarial_input.csv", data, FIELDS)
    for name, retune in (("default", False), ("retuned", True)):
        output = process(data, retune)
        write_csv(ROOT / f"expected_{name}_samples.csv", output, OUTPUT)
        (ROOT / f"expected_{name}_minutes.json").write_text(json.dumps(json_finite(minute_summary(data, output)), indent=2, allow_nan=False) + "\n", encoding="utf-8")
    for edge in ("all_invalid", "wind_overflow"):
        edge_data = []
        for i in range(600):
            row = dict(zip(FIELDS, [i / FS, 20.0, 50.0, 0.0, 0.0, 1010.0, 0]))
            if edge == "all_invalid":
                for key in FIELDS[1:6]:
                    row[key] = math.nan
            else:
                row["WIND_U_MPS"] = row["WIND_V_MPS"] = float.fromhex("0x1.fffffffffffffp+1023")
            edge_data.append(row)
        edge_out = process(edge_data)
        write_csv(ROOT / f"{edge}_input.csv", edge_data, FIELDS)
        write_csv(ROOT / f"expected_{edge}_samples.csv", edge_out, OUTPUT)
        (ROOT / f"expected_{edge}_minutes.json").write_text(json.dumps(json_finite(minute_summary(edge_data, edge_out)), indent=2, allow_nan=False) + "\n", encoding="utf-8")
    manifest = {
        "provenance": "Independent Python numerical reference; MATLAB comparison NOT yet executed",
        "input_rows": 1201, "complete_minute_count": 2, "partial_tail_rows": 1,
        "default": "All rows use per-pole cutoff0.2Hz",
        "retuned": "Change per-pole cutoff to0.3Hz before processing time_s=60.0; retain all state",
        "edge_fixtures": "all_invalid and wind_overflow each have600samples/one fullminute and use default0.2Hz cutoff. The corresponding expected_*_samples.csv and expected_*_minutes.json describe them. Missing JSON numeric values are null.",
        "comparison": "Numeric finite fields: abs error<=1e-9 +1e-10*abs(expected). NaN masks and quality/window flags must match exactly. Direction differences require circular modulo360 comparison. Compare UTC minute fields separately, ignoring wall-clock generated_at.",
        "input_events": ["Two leading temperature dropouts", "5C plunge at30s with two subsequent temperature gaps and one out-of-range sample", "20pp persistent humidity jump and return", "Explicit0/100 endpoint faults", "6s humidity dropout with recovery", "359/1deg wind seam", "9m/s gust at15s", "Wind gaps and finite-component/hypot overflow", "Long calm tail", "Pressure dropouts/out-of-range", "2full UTC minutes plus1 trailing sample"],
        "limitations": ["Does not validate integer numeric-class handling; dedicated MATLAB tests are required", "Does not execute MATLAB parser, app, or timers", "Is not an official KMA contract or observed-weather benchmark"]
    }
    (ROOT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote golden contract reference to {ROOT}")
