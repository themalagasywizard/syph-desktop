"""End-to-end check of Syph for Mac's computer control on a real Mac.

A stdlib stand-in for the Syph API speaks the same wire contract as
`services/api/app/devices.py` (auth, workspace, device register/heartbeat,
long-poll, result). The real app signs in, links itself, and executes the
queued commands for real; this script asserts on what it reports back.
The server side of the contract is covered by the backend's test_devices.py.
"""
import json
import socketserver
import os
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MARKER = f"syph-e2e-{uuid.uuid4().hex[:8]}"
CASES = [
    ("observe", {}, True),
    ("list_files", {}, True),
    ("write_file", {"path": "e2e/hello.txt", "content": MARKER}, True),
    ("read_file", {"path": "e2e/hello.txt"}, True),
    ("list_files", {"path": "e2e"}, True),
    ("read_file", {"path": "/etc/hosts"}, False),  # outside shared folders: must be refused
    ("run_shell", {"command": "cat e2e/hello.txt && echo shell-ok"}, True),
    ("applescript", {"script": "return (2 + 3) as text"}, True),
    ("clipboard_write", {"text": MARKER}, True),
    ("clipboard_read", {}, True),
    ("open_app", {"app": "TextEdit"}, True),
    ("quit_app", {"app": "TextEdit"}, True),
    ("open_url", {"url": "file:///etc/passwd"}, False),  # only web-style links
    ("read_screen", {}, None),  # needs Screen Recording; reported either way
    ("read_ui", {}, None),      # needs Accessibility; reported either way
    ("trash_file", {"path": "e2e/hello.txt"}, True),
]

lock = threading.Lock()
queue = [
    {"id": str(uuid.uuid4()), "operation": op, "arguments": args, "expect": expect}
    for op, args, expect in CASES
]
results: dict[str, dict] = {}
devices: dict[str, dict] = {}
SESSION = "e2e-session"


def command_out(cmd):
    return {
        "id": cmd["id"], "deviceId": None, "employeeId": "e1", "employeeName": "Atlas", "runId": None,
        "operation": cmd["operation"], "arguments": cmd["arguments"], "status": "delivered", "summary": "",
        "result": {}, "createdAt": "2026-09-26T10:00:00Z", "completedAt": None, "expiresAt": None,
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, body, headers=None):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}") if length else {}

    def authed(self):
        return f"session={SESSION}" in (self.headers.get("Cookie") or "")

    def route(self, method):
        url = urlparse(self.path)
        path = url.path.rstrip("/")
        payload = self.body() if method in {"POST", "PUT", "PATCH"} else {}
        if path == "/health":
            return self.reply(200, {"ok": True})
        if path == "/api/v1/auth/login" and method == "POST":
            user = {"id": "u1", "name": "Ryan", "email": payload.get("email", ""), "role": "Owner"}
            return self.reply(200, user, {"Set-Cookie": f"session={SESSION}; Path=/; HttpOnly"})
        if not self.authed():
            return self.reply(401, {"detail": "Not signed in"})
        if path == "/api/v1/auth/me":
            return self.reply(200, {"id": "u1", "name": "Ryan", "email": "ryan@jarvis.local", "role": "Owner"})
        if path == "/api/v1/workspace":
            return self.reply(200, {
                "user": {"id": "u1", "name": "Ryan", "email": "ryan@jarvis.local", "role": "Owner"},
                "employees": [{"id": "e1", "name": "Atlas", "role": "Operations", "mission": "Desktop chores",
                               "status": "active", "toolIds": ["computer"]}],
                "approvals": [], "activity": [], "jobs": [], "conversations": [], "messages": [],
                "accountTools": [], "employeeTools": [],
            })
        if path.endswith("/working"):
            return self.reply(200, {"active": False, "runId": None, "status": "idle", "goal": "", "phase": "", "steps": []})
        if path == "/api/v1/devices" and method == "GET":
            return self.reply(200, list(devices.values()))
        parts = path.split("/")
        if len(parts) >= 5 and parts[3] == "devices":
            device_id = parts[4]
            if len(parts) == 5 and method == "PUT":
                devices[device_id] = {"id": device_id, "online": True, "lastSeenAt": None, **{
                    k: payload.get(k) for k in ("name", "platform", "model", "osVersion", "appVersion", "controlEnabled", "scopes")}}
                print(f"linked {payload.get('name')} scopes={payload.get('scopes')} control={payload.get('controlEnabled')}", flush=True)
                return self.reply(200, devices[device_id])
            if device_id not in devices:
                return self.reply(404, {"detail": "Device not found"})
            if parts[-1] == "heartbeat":
                devices[device_id].update({k: v for k, v in payload.items() if v is not None})
                return self.reply(200, devices[device_id])
            if parts[-1] == "next":
                wait = float(parse_qs(url.query).get("wait", ["0"])[0])
                deadline = time.monotonic() + wait
                while True:
                    with lock:
                        pending = next((c for c in queue if c["id"] not in results and not c.get("sent")), None)
                        busy = any(c.get("sent") and c["id"] not in results for c in queue)
                        if pending and not busy:
                            pending["sent"] = True
                            return self.reply(200, {"command": command_out(pending)})
                    if time.monotonic() >= deadline:
                        return self.reply(200, {"command": None})
                    time.sleep(0.2)
            if len(parts) == 7 and parts[5] == "commands" and method == "POST":
                command_id = parts[6]
                if payload.get("status") != "running":
                    with lock:
                        results[command_id] = payload
                return self.reply(200, {"id": command_id, "status": payload.get("status"), "operation": "", "arguments": {},
                                        "summary": payload.get("summary", ""), "createdAt": "", "deviceId": device_id,
                                        "employeeId": None, "runId": None, "completedAt": None, "expiresAt": None})
        return self.reply(404, {"detail": f"No route {method} {path}"})

    def do_GET(self): self.route("GET")
    def do_POST(self): self.route("POST")
    def do_PUT(self): self.route("PUT")
    def do_PATCH(self): self.route("PATCH")
    def do_DELETE(self): self.route("DELETE")


class Server(ThreadingHTTPServer):
    # HTTPServer.server_bind() calls socket.getfqdn(), a reverse lookup that goes
    # to mDNS and stalls behind macOS's Local Network prompt on CI runners.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def main() -> int:
    server = Server(("127.0.0.1", int(os.environ.get("PORT", "8765"))), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print("mock API listening", flush=True)
    deadline = time.monotonic() + float(os.environ.get("E2E_TIMEOUT", "300"))
    while time.monotonic() < deadline and len(results) < len(queue):
        time.sleep(0.5)
    failures = 0
    for cmd in queue:
        got = results.get(cmd["id"])
        if got is None:
            print(f"[MISSING]    {cmd['operation']}")
            failures += 1
            continue
        ok = got.get("status") == "succeeded"
        data = got.get("data") or {}
        slim = {k: v for k, v in data.items() if k not in {"lines", "elements", "running_apps", "windows", "_image", "entries"}}
        verdict = "ok" if cmd["expect"] is None or ok == cmd["expect"] else "UNEXPECTED"
        checks = {
            "read_file": lambda: MARKER in data.get("content", ""),
            "run_shell": lambda: "shell-ok" in data.get("stdout", "") and MARKER in data.get("stdout", ""),
            "applescript": lambda: data.get("stdout", "").strip() == "5",
            "clipboard_read": lambda: data.get("content") == MARKER,
        }
        if ok and cmd["operation"] in checks and not checks[cmd["operation"]]():
            verdict = "WRONG DATA"
        if verdict != "ok":
            failures += 1
        extra = f" lines={len(data.get('lines', []))}" if "lines" in data else ""
        extra += f" elements={len(data.get('elements', []))}" if "elements" in data else ""
        extra += f" thumbnail={'yes' if data.get('_image') else 'no'}" if cmd["operation"] == "read_screen" else ""
        print(f"[{verdict:10s}] {cmd['operation']:15s} {got.get('status'):9s} {got.get('summary', '')}{extra}  {json.dumps(slim)[:220]}")
    print(f"{len(queue) - failures}/{len(queue)} cases as expected", flush=True)
    server.shutdown()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
