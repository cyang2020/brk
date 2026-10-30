#!/usr/bin/env python3
"""Drive this checkout's CEF app through immediate download shutdown, optionally under LLDB."""
import argparse
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import threading
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True)
    parser.add_argument("--active", action="store_true")
    parser.add_argument("--lldb", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    out = (root / args.out).resolve()
    if not out.is_relative_to(root):
        parser.error("--out must be inside this checkout")
    out.mkdir(parents=True, exist_ok=True)
    data = out / "data"
    if data.exists():
        parser.error("choose a fresh --out directory so no previous download can satisfy the check")
    data.mkdir(exist_ok=True)
    socket_path = root / f".f5-{os.getpid()}.sock"
    release_body = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            downloading = self.path == "/download"
            body = b"fixture download\n" if downloading else b"<title>Fixture Home</title>"
            if downloading and args.active:
                body = b"A" * 65_536
            self.send_response(200)
            self.send_header("Content-Type", "text/plain" if downloading else "text/html")
            if downloading:
                self.send_header("Content-Disposition", 'attachment; filename="fixture.txt"')
            self.send_header("Content-Length", str(1024 * 1024 if downloading and args.active else len(body)))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            if downloading and args.active:
                release_body.wait(30)

        def log_message(self, *_):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    env = {k: v for k, v in os.environ.items() if not k.startswith("BRK_")}
    env.update(BRK_DATA_DIR=str(data), BRK_CONTROL_SOCKET=str(socket_path), BRK_START_URL=base)
    executable = root / "dist/Brk.app/Contents/MacOS/Brk"
    command = [str(executable)]
    if args.lldb:
        command = ["/usr/bin/lldb", "--batch", "-o", "run", "-k", "thread backtrace all",
                   "-k", "register read", "-k", "image list -o -f", "-k", "process kill", "--", str(executable)]
    with (out / "native.log").open("w") as log:
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(10)
        request_id = 0

        def send(op):
            nonlocal request_id
            request_id += 1
            client.sendall((json.dumps({"id": request_id, "op": op}) + "\n").encode())
            response = b""
            while not response.endswith(b"\n"):
                chunk = client.recv(65536)
                if not chunk:
                    raise RuntimeError("Brk closed the control socket")
                response += chunk
            return json.loads(response)["result"]

        def dispatch(command):
            return send({"dispatch": {"command": command}})

        try:
            deadline = time.monotonic() + 30
            while True:
                try:
                    client.connect(str(socket_path))
                    break
                except (FileNotFoundError, ConnectionRefusedError):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("Brk did not open the control socket; see native.log")
                    time.sleep(0.05)
            send({"hello": {}})
            dispatch({"settings": {"_0": {"profile": {"_0": "default", "_1": {
                "downloadsDirectory": {"_0": str(data / "downloads")}}}}}})
            send({"load": {"url": base + "/download"}})
            dispatch({"library": {"_0": {"open": {"_0": "downloads"}}}})
            deadline = time.monotonic() + 15
            while True:
                view = send({"view": {}})
                (out / "last-view.json").write_text(json.dumps(view, indent=2))
                rows = view["view"]["_0"].get("overlay", {}).get("library", {}).get("_0", {}).get("downloads", [])
                if rows and (rows[0]["state"] == "inProgress" and rows[0]["received"] > 0 if args.active else rows[0]["state"] == "finished"):
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError("download did not reach the requested state; see last-view.json")
                time.sleep(0.01)
            start = time.monotonic()
            send({"quit": {}})
            client.close()
            status = process.wait(timeout=20)
            seconds = time.monotonic() - start
            native_log = (out / "native.log").read_text()
            crashed = "stop reason =" in native_log or "fatal signal" in native_log
            result = {"exit_status": status, "native_crash": crashed, "quit_seconds": seconds,
                      "download_at_quit": rows[0], "mode": "active" if args.active else "completed"}
            (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result))
            if status != 0 or crashed:
                raise SystemExit(1)
        finally:
            release_body.set()
            client.close()
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            socket_path.unlink(missing_ok=True)
            server.shutdown()


if __name__ == "__main__":
    main()
