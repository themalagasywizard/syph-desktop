"""Agent-level evaluation of Syph computer control on a real Windows PC.

Sends each task in agent_tasks.json to a real employee (with the Computer tool)
on a real Syph server, waits for the run, then checks the outcome on this PC with
the task's PowerShell verify script. Needs the Syph app running on this PC,
signed in to the same workspace, with computer control on.

    SYPH_SERVER=https://…  SYPH_EMAIL=…  SYPH_PASSWORD=…  SYPH_EMPLOYEE=<name or id>
    python ci/agent_eval.py [task-id …]

Writes agent-eval.json and a Markdown table (also to $GITHUB_STEP_SUMMARY).
Stdlib only.
"""
from __future__ import annotations

import http.cookiejar
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).parent
SYPH = os.environ.get("SYPH", str(Path.home() / "Documents" / "Syph"))
OUT = Path(os.environ.get("SYPH_EVAL_OUT", Path.cwd() / "agent-eval-out"))
FINAL = {"completed", "failed", "waiting_for_approval", "cancelled"}

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))


def api(method: str, path: str, body: dict | None = None) -> dict:
    url = os.environ["SYPH_SERVER"].rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    with opener.open(request, timeout=60) as response:
        text = response.read().decode()
        return json.loads(text) if text else {}


def powershell(script: str, timeout: int = 120) -> int:
    env = {**os.environ, "SYPH": SYPH, "SYPH_EVAL_OUT": str(OUT)}
    exe = shutil.which("powershell") or "powershell"
    try:
        return subprocess.run([exe, "-NoProfile", "-NonInteractive", "-Command", script], env=env, timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        return 124


class FormSite(BaseHTTPRequestHandler):
    """A tiny contact form for the web-form task; submissions go to form-submissions.json."""
    PAGE = b"""<!doctype html><title>Contact us</title><h1>Contact us</h1>
<form method=post action=/submit><label>Name <input name=name></label><br><label>Email <input name=email type=email></label><br>
<label>Message <textarea name=message></textarea></label><br><button type=submit>Send</button></form>"""

    def log_message(self, *args):
        pass

    ABOUT = """<!doctype html><title>Northwind Traders</title><h1>Northwind Traders</h1><h2>Opening hours</h2>
<table><tr><td>Monday to Friday</td><td>8:30 am – 6 pm</td></tr><tr><td>Saturday</td><td>9 am – 1 pm</td></tr>
<tr><td>Sunday</td><td>Closed</td></tr></table>""".encode()

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        page = self.PAGE if self.path.startswith("/form") else self.ABOUT if self.path.startswith("/about") else b"<h1>Thanks, we got your message.</h1>"
        self.wfile.write(page)

    def do_POST(self):
        fields = urllib.parse.parse_qs(self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode())
        entry = {k: v[0] for k, v in fields.items()}
        target = OUT / "form-submissions.json"
        rows = json.loads(target.read_text()) if target.exists() else []
        target.write_text(json.dumps([*rows, entry]))
        self.send_response(303)
        self.send_header("Location", "/thanks")
        self.end_headers()


def has(requirement: str | None) -> bool:
    if requirement == "excel":
        return powershell("try { $x = New-Object -ComObject Excel.Application; $x.Quit(); exit 0 } catch { exit 1 }", 60) == 0
    return True


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    Path(SYPH).mkdir(parents=True, exist_ok=True)
    tasks = json.loads((HERE / "agent_tasks.json").read_text(encoding="utf-8"))["tasks"]
    only = set(sys.argv[1:])
    if only:
        tasks = [t for t in tasks if t["id"] in only]

    server = ThreadingHTTPServer(("127.0.0.1", 8777), FormSite)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    api("POST", "/api/v1/auth/login", {"email": os.environ["SYPH_EMAIL"], "password": os.environ["SYPH_PASSWORD"]})
    workspace = api("GET", "/api/v1/workspace")
    wanted = os.environ.get("SYPH_EMPLOYEE", "")
    employee = next((e for e in workspace["employees"] if wanted in (e["id"], e["name"])), None)
    if employee is None or "computer" not in (employee.get("toolIds") or []):
        print(f"Employee {wanted!r} not found or without the Computer tool.")
        return 2

    results = []
    for task in tasks:
        started = time.monotonic()
        if not has(task.get("requires")):
            results.append({"id": task["id"], "status": "skipped", "reason": f"needs {task['requires']}"})
            print(f"[skip] {task['id']}: needs {task['requires']}")
            continue
        powershell(task.get("setup", ""))
        run_id = api("POST", f"/api/v1/employees/{employee['id']}/instructions", {"body": task["prompt"]})["runId"]
        run: dict = {}
        deadline = time.monotonic() + int(task.get("timeout", 900))
        while time.monotonic() < deadline:
            time.sleep(5)
            run = api("GET", f"/api/v1/runs/{run_id}")
            if run.get("status") in FINAL:
                break
        passed = powershell(task["verify"]) == 0
        seconds = round(time.monotonic() - started)
        results.append({"id": task["id"], "status": "pass" if passed else "fail", "run_status": run.get("status"),
                        "stop_reason": run.get("stopReason"), "seconds": seconds, "run_id": run_id,
                        "reply": str(run.get("result") or "")[:500]})
        print(f"[{'pass' if passed else 'FAIL'}] {task['id']} ({seconds}s, run {run.get('status')})", flush=True)

    server.shutdown()
    scored = [r for r in results if r["status"] != "skipped"]
    passed = sum(r["status"] == "pass" for r in scored)
    (OUT / "agent-eval.json").write_text(json.dumps({"passed": passed, "total": len(scored), "results": results}, indent=2))
    table = ["| Task | Result | Time | Run |", "| --- | --- | --- | --- |"] + [
        f"| {r['id']} | {r['status']} | {r.get('seconds', '')}s | {r.get('run_status', r.get('reason', ''))} |" for r in results]
    summary = f"### Syph agent eval: {passed}/{len(scored)} passed\n\n" + "\n".join(table) + "\n"
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(summary)
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
