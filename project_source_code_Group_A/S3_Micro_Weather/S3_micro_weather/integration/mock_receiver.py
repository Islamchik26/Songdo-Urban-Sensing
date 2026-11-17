#!/usr/bin/env python3
"""Local Sensor Grid mock validator; NOT a KMA service or official KMA schema.

Validate without serving: python integration/mock_receiver.py --validate FILE
Optional local HTTP: python integration/mock_receiver.py --serve
Binds loopback only; accepted requests append to a local JSONL file.
"""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import math
from pathlib import Path
from http.server import BaseHTTPRequestHandler, HTTPServer

CHANNEL_UNITS = {"AIR_TEMP_C": "degC", "REL_HUMIDITY_PCT": "%",
                 "WIND_SPEED_MPS": "m/s", "WIND_DIR_DEG": "deg"}
FLAGS = {"GOOD", "DROPOUT", "OUT_OF_RANGE", "SUSPECT_JUMP"}
TOP = {"schema_version", "generated_at", "station_id", "latitude", "longitude", "records"}
RECORD = {"timestamp", "channel", "raw_value", "filtered_value", "unit", "quality_flag"}


def timestamp(value):
    if not isinstance(value, str) or len(value) != 24 or not value.endswith("Z"):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%fZ")
        return True
    except ValueError:
        return False


def number(value):
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def validate(data):
    errors = []
    if not isinstance(data, dict) or set(data) != TOP:
        return ["Top-level fields must exactly match the local Sensor Grid schema."]
    if data["schema_version"] != "1.0":
        errors.append("schema_version must be 1.0")
    if data["station_id"] != "STATION_CENTRAL_PARK_WEATHER":
        errors.append("station_id is not the configured S3 station")
    if not timestamp(data["generated_at"]):
        errors.append("generated_at must be a valid millisecond ISO-8601 UTC timestamp")
    for key, limit in (("latitude", 90), ("longitude", 180)):
        if not number(data[key]) or abs(data[key]) > limit:
            errors.append(f"{key} must be a finite coordinate")
    records = data["records"]
    if not isinstance(records, list) or not records:
        return errors + ["records must be a nonempty array"]
    seen = set()
    groups = {}
    for i, record in enumerate(records):
        prefix = f"records[{i}]"
        if not isinstance(record, dict) or set(record) != RECORD:
            errors.append(f"{prefix}: incorrect record fields")
            continue
        channel, flag = record["channel"], record["quality_flag"]
        if not isinstance(channel, str) or channel not in CHANNEL_UNITS:
            errors.append(f"{prefix}: unknown registered channel")
        elif record["unit"] != CHANNEL_UNITS[channel]:
            errors.append(f"{prefix}: unit mismatch")
        if not isinstance(flag, str) or flag not in FLAGS:
            errors.append(f"{prefix}: invalid quality flag")
        if not timestamp(record["timestamp"]):
            errors.append(f"{prefix}: invalid UTC timestamp")
        for key in ("raw_value", "filtered_value"):
            value = record[key]
            if value is None:
                if flag == "GOOD":
                    errors.append(f"{prefix}: missing {key} cannot be GOOD")
            elif not number(value):
                errors.append(f"{prefix}: {key} must be finite numeric or null")
        if isinstance(record["timestamp"], str) and isinstance(channel, str):
            key = record["timestamp"], channel
            if key in seen:
                errors.append(f"{prefix}: duplicate minute/channel")
            seen.add(key)
            groups.setdefault(record["timestamp"], set()).add(channel)
    for time, channels in groups.items():
        if channels != set(CHANNEL_UNITS):
            errors.append(f"{time}: minute must contain exactly four registered channels")
    return errors


def load_strict(text):
    def invalid_constant(value):
        raise ValueError(f"Nonstandard JSON constant: {value}")
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(text, parse_constant=invalid_constant, object_pairs_hook=unique_keys)


def serve(port, output):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/api/v1/telemetry":
                self.send_error(404)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size <= 0 or size > 2_000_000:
                    raise ValueError("Body must be between 1 byte and 2 MB")
                data = load_strict(self.rfile.read(size).decode("utf-8"))
                errors = validate(data)
            except (ValueError, UnicodeDecodeError) as exc:
                data, errors = None, [str(exc)]
            body = json.dumps({"accepted": not errors, "schema_violations": len(errors), "errors": errors}).encode()
            if not errors:
                output.parent.mkdir(parents=True, exist_ok=True)
                with output.open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps(data, allow_nan=False) + "\n")
            self.send_response(422 if errors else 200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    print(f"Local mock only: http://127.0.0.1:{port}/api/v1/telemetry")
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--validate", type=Path)
    action.add_argument("--serve", action="store_true")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("received_telemetry.jsonl"))
    args = parser.parse_args()
    if args.serve:
        serve(args.port, args.output)
    else:
        try:
            errors = validate(load_strict(args.validate.read_text(encoding="utf-8")))
        except (ValueError, OSError) as exc:
            errors = [str(exc)]
        print(json.dumps({"schema_violations": len(errors), "errors": errors}, indent=2))
        raise SystemExit(bool(errors))


if __name__ == "__main__":
    main()
