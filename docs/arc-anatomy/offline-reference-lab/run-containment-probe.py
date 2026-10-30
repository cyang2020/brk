#!/usr/bin/env python3
"""Run an owned sentinel probe. Never copies, launches, or modifies Arc."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent


def main():
    root = Path(tempfile.mkdtemp(prefix="arc-reference-gate.")).resolve()
    allowed, outside = root / "allowed", root / "outside"
    allowed.mkdir()
    outside.mkdir()
    (allowed / "tmp").mkdir()
    sentinel = outside / "sentinel"
    sentinel.write_bytes(b"owned sentinel, must stay unchanged\n")
    original = hashlib.sha256(sentinel.read_bytes()).hexdigest()
    result = {"kind": "ordinary-shell-observation", "root": str(root),
              "arc_launched": False, "sentinel_before_sha256": original}
    try:
        command = ["/usr/bin/xcrun", "clang", str(HERE / "probe.c"), "-o", str(root / "probe")]
        build = subprocess.run(command, capture_output=True, text=True, timeout=45)
        result["compile"] = {"argv": command, "exit": build.returncode,
                             "stdout": build.stdout, "stderr": build.stderr}
        if build.returncode == 0:
            command = ["/usr/bin/sandbox-exec", "-D", f"ROOT={root}", "-D", f"WRITE={allowed}",
                       "-f", str(HERE / "probe.sb"), str(root / "probe"),
                       str(allowed / "marker"), str(sentinel)]
            env = {"PATH": "/usr/bin:/bin", "HOME": str(allowed),
                   "CFFIXED_USER_HOME": str(allowed), "TMPDIR": str(allowed / "tmp")}
            run = subprocess.run(command, env=env, cwd=root, close_fds=True,
                                 capture_output=True, text=True, timeout=15)
            result["probe"] = {"argv": command, "environment": env, "exit": run.returncode,
                               "stdout": run.stdout, "stderr": run.stderr}
        result["sentinel_after_sha256"] = hashlib.sha256(sentinel.read_bytes()).hexdigest()
        result["sentinel_unchanged"] = result["sentinel_after_sha256"] == original
        result["allowed_marker_exists"] = (allowed / "marker").exists()
        result["gate"] = "NOT_ESTABLISHED"
        result["scope"] = "Direct file/socket/Mach probe only; not an Arc GUI or daemon-write proof."
    finally:
        shutil.rmtree(root)
        result["owned_root_removed"] = not root.exists()
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
