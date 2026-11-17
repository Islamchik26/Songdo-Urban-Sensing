from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
from datetime import datetime, timezone

HOST, PORT = "127.0.0.1", 8080
LOG_PATH = Path(__file__).resolve().parent / "received_telemetry.jsonl"

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/api/v1/telemetry":
            self.send_error(404, "Unknown endpoint")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            packet = json.loads(self.rfile.read(length).decode("utf-8"))
            required = {"schema_version", "generated_at", "station_id",
                        "latitude", "longitude", "records"}
            if not required.issubset(packet):
                raise ValueError("Missing required packet fields")
            if packet["station_id"] != "STATION_CONVENSIA":
                raise ValueError("Unexpected station_id")
            if not isinstance(packet["records"], list) or not packet["records"]:
                raise ValueError("records must be a non-empty list")
            record_fields = {"timestamp", "channel", "raw_value",
                             "filtered_value", "unit", "quality_flag"}
            for record in packet["records"]:
                if not record_fields.issubset(record):
                    raise ValueError("Missing record field")
            with LOG_PATH.open("a", encoding="utf-8") as f:
                f.write(json.dumps(packet, ensure_ascii=False) + "\n")
            body = json.dumps({"status": "ok",
                "received_records": len(packet["records"]),
                "received_at": datetime.now(timezone.utc).isoformat()}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception as exc:
            body = json.dumps({"status": "error", "message": str(exc)}).encode()
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")

if __name__ == "__main__":
    print(f"S1 mock receiver: http://{HOST}:{PORT}/api/v1/telemetry")
    print(f"Audit log: {LOG_PATH}")
    HTTPServer((HOST, PORT), Handler).serve_forever()
