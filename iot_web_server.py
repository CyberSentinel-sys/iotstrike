#!/usr/bin/env python3
"""
IoTStrike Web API Server
Serves the dashboard and exposes REST endpoints that trigger IoTStrike.sh flags.

Author:  Yechiel Said
GitHub:  https://github.com/CyberSentinel-sys
Email:   yechielstudy@gmail.com
Issues:  https://github.com/CyberSentinel-sys/iotstrike/issues

Usage:
    sudo python3 iot_web_server.py            # listens on 127.0.0.1:8080
    sudo python3 iot_web_server.py --port 9090
    sudo python3 iot_web_server.py --host 0.0.0.0  # expose to LAN (use with care)

Authentication:
    A random API key is generated on startup and printed to the console.
    All /api/* endpoints require either:
      - HTTP header:   Authorization: Bearer <api_key>
      - Query param:   ?api_key=<api_key>

Endpoints:
    GET  /                      → serves index.html
    GET  /status.json           → serves live status.json (no auth required)
    POST /api/upload            → firmware upload  → triggers --emulate <path>
    POST /api/command           → JSON action       → triggers --scan / --cve
    GET  /api/status            → returns parsed status.json
    GET  /api/logs/<filename>   → last 100 lines of a log file
"""

import argparse
import functools
import json
import os
import secrets
import subprocess
import threading
from pathlib import Path

# Flask is installed by default on Kali; fall back gracefully if missing
try:
    from flask import Flask, jsonify, request, send_from_directory
    from werkzeug.utils import secure_filename
except ImportError:
    print("[✗] Flask not found. Install with:  pip install flask")
    raise SystemExit(1)

# ── Config ─────────────────────────────────────────────────────────────────────
BASE_DIR   = Path("/opt/iotstrike")
WEB_DIR    = BASE_DIR / "web"
UPLOAD_DIR = BASE_DIR / "uploads"
LOG_DIR    = BASE_DIR / "logs"
RUNNER     = BASE_DIR / "IoTStrike.sh"

ALLOWED_EXTENSIONS = {".zip", ".bin", ".tar", ".gz", ".img", ".trx", ".chk", ".dlf", ".w"}

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)
WEB_DIR.mkdir(parents=True, exist_ok=True)

# Always ensure status.json exists with valid content so the dashboard never
# receives an empty string or a 404 that breaks JSON.parse on the client side.
_STATUS_FILE = WEB_DIR / "status.json"
_EMPTY_STATUS = {
    "target_ip": "none",
    "vendor": "unknown",
    "arch": "",
    "emulator": "",
    "session": "none",
    "ports": [],
    "cves": [],
    "scan_summary": "No scan data yet",
}
if not _STATUS_FILE.exists() or _STATUS_FILE.stat().st_size == 0:
    _STATUS_FILE.write_text(json.dumps(_EMPTY_STATUS, indent=2))

app = Flask(__name__, static_folder=str(WEB_DIR))

# ── API Key Authentication ──────────────────────────────────────────────────────
# A fresh 48-character hex key is generated each time the server starts.
# It is printed to the console on startup and must be supplied by all callers
# of /api/* endpoints via  Authorization: Bearer <key>  or  ?api_key=<key>.
API_KEY: str = secrets.token_hex(24)


def _require_auth(f):
    """Decorator that enforces API key auth on /api/* routes."""
    @functools.wraps(f)
    def _decorated(*args, **kwargs):
        # Bearer token check
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            if secrets.compare_digest(auth_header[7:], API_KEY):
                return f(*args, **kwargs)
        # Query-parameter fallback (?api_key=...)
        qp = request.args.get("api_key", "")
        if qp and secrets.compare_digest(qp, API_KEY):
            return f(*args, **kwargs)
        return jsonify({"error": "Forbidden — invalid or missing API key"}), 403
    return _decorated


# ── Helpers ────────────────────────────────────────────────────────────────────
def _allowed(filename: str) -> bool:
    return Path(filename).suffix.lower() in ALLOWED_EXTENSIONS


def _run_bg(cmd: list[str], log_path: Path) -> None:
    """Run a command in a background thread, writing stdout+stderr to log_path."""
    def _worker():
        with open(log_path, "w") as lf:
            subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT)
    threading.Thread(target=_worker, daemon=True).start()


def _read_status() -> dict:
    status_file = WEB_DIR / "status.json"
    try:
        with open(status_file) as f:
            return json.load(f)
    except Exception:
        return {}


# ── Static files ───────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return send_from_directory(str(WEB_DIR), "index.html")


@app.route("/status.json")
def status():
    # Always return valid JSON with the correct content-type header.
    # send_from_directory returns a 404 if the file is missing, which
    # causes JSON.parse to fail on the client; _read_status() never raises.
    from flask import Response
    return Response(
        json.dumps(_read_status(), indent=2),
        mimetype="application/json",
    )


# ── POST /api/upload ───────────────────────────────────────────────────────────
@app.route("/api/upload", methods=["POST"])
@_require_auth
def api_upload():
    """
    Accepts a multipart/form-data upload with field name 'firmware'.
    Saves the file to UPLOAD_DIR and triggers:
        sudo bash IoTStrike.sh --emulate <saved_path>
    in the background.

    Returns JSON:
        { "status": "started", "file": "<filename>", "path": "<full_path>" }
    """
    if "firmware" not in request.files:
        return jsonify({"error": "No 'firmware' field in request"}), 400

    f = request.files["firmware"]
    if not f.filename:
        return jsonify({"error": "Empty filename"}), 400

    filename = secure_filename(f.filename)
    if not _allowed(filename):
        return jsonify({
            "error": f"Unsupported file type. Allowed: {sorted(ALLOWED_EXTENSIONS)}"
        }), 400

    save_path = UPLOAD_DIR / filename
    f.save(str(save_path))

    log_path = LOG_DIR / f"emulate_{filename}.log"
    cmd = ["sudo", "bash", str(RUNNER), "--emulate", str(save_path)]
    _run_bg(cmd, log_path)

    return jsonify({
        "status":  "started",
        "action":  "emulate",
        "file":    filename,
        "path":    str(save_path),
        "log":     str(log_path),
    })


# ── POST /api/command ──────────────────────────────────────────────────────────
@app.route("/api/command", methods=["POST"])
@_require_auth
def api_command():
    """
    Accepts JSON body:
        { "action": "scan",  "value": "192.168.0.100" }
        { "action": "cve",   "value": "netgear" }

    Triggers the matching IoTStrike.sh flag in the background.

    Returns JSON:
        { "status": "started", "action": "scan", "target": "192.168.0.100" }
    """
    data = request.get_json(force=True, silent=True) or {}
    action = data.get("action", "").strip().lower()
    value  = data.get("value",  "").strip()

    FLAG_MAP = {
        "scan": "--scan",
        "cve":  "--cve",
    }

    if action not in FLAG_MAP:
        return jsonify({
            "error": f"Unknown action '{action}'. Allowed: {sorted(FLAG_MAP)}"
        }), 400

    if not value:
        return jsonify({"error": "Missing or empty 'value' field"}), 400

    # Basic input sanity — no shell metacharacters
    import re
    if not re.match(r'^[A-Za-z0-9._:\-]+$', value):
        return jsonify({"error": f"Invalid value: {value!r}"}), 400

    log_path = LOG_DIR / f"{action}_{value.replace('.', '_')}.log"
    cmd = ["sudo", "bash", str(RUNNER), FLAG_MAP[action], value]
    _run_bg(cmd, log_path)

    return jsonify({
        "status": "started",
        "action": action,
        "target": value,
        "log":    str(log_path),
    })


# ── GET /api/status ────────────────────────────────────────────────────────────
@app.route("/api/status")
@_require_auth
def api_status():
    """Returns the parsed status.json as JSON (same as /status.json but via API)."""
    return jsonify(_read_status())


# ── GET /api/logs/<filename> ───────────────────────────────────────────────────
@app.route("/api/logs/<path:filename>")
@_require_auth
def api_logs(filename):
    """Stream the last 100 lines of a background job log file."""
    log_file = LOG_DIR / filename
    if not log_file.exists():
        return jsonify({"error": "Log not found"}), 404
    # Only serve files inside LOG_DIR (prevent path traversal)
    try:
        log_file.resolve().relative_to(LOG_DIR.resolve())
    except ValueError:
        return jsonify({"error": "Forbidden"}), 403
    lines = log_file.read_text(errors="replace").splitlines()[-100:]
    return jsonify({"lines": lines})


# ── Entry point ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="IoTStrike Web API Server")
    parser.add_argument("--port", type=int, default=8080,
                        help="Port to listen on (default: 8080)")
    parser.add_argument("--host", default="127.0.0.1",
                        help="Host to bind to (default: 127.0.0.1 — localhost only)")
    args = parser.parse_args()

    if os.geteuid() != 0:
        print("[!] Warning: not running as root. "
              "sudo calls inside IoTStrike.sh may fail.")

    print(f"[*] IoTStrike Web API — http://{args.host}:{args.port}")
    print(f"[*] Serving dashboard from {WEB_DIR}")
    print(f"[*] Runner:  {RUNNER}")
    print(f"[*] Uploads: {UPLOAD_DIR}")
    print()
    print(f"[+] ─────────────────────────────────────────────────────")
    print(f"[+]  API KEY (generated at startup — keep this secret):")
    print(f"[+]  {API_KEY}")
    print(f"[+] ─────────────────────────────────────────────────────")
    print(f"[*] All /api/* endpoints require this key via:")
    print(f"[*]   Header:  Authorization: Bearer {API_KEY}")
    print(f"[*]   Param:   ?api_key={API_KEY}")
    print()
    app.run(host=args.host, port=args.port, debug=False, threaded=True)
