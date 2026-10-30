#!/usr/bin/env python3
"""Read installed bytes and recheck the previous report's seven arm64 branches."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess

HERE = Path(__file__).resolve().parent
APP = Path("/Applications/Arc.app")
EXE = APP / "Contents/MacOS/Arc"
CACHE = Path("/Users/administrator/.cache/arc-target-arm64/Arc")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    data = EXE.read_bytes()
    assert data[:4] == b"\xca\xfe\xba\xbe", "Unexpected universal Mach-O format"
    count = struct.unpack_from(">I", data, 4)[0]
    slices = [struct.unpack_from(">IIIII", data, 8 + 20 * i) for i in range(count)]
    arm = [s for s in slices if s[0] == 0x100000C]
    assert len(arm) == 1
    _, _, offset, size, _ = arm[0]
    thin = data[offset:offset + size]
    assert len(thin) == size and thin[:4] == b"\xcf\xfa\xed\xfe"
    segments = []
    cursor = 32
    for _ in range(struct.unpack_from("<I", thin, 16)[0]):
        cmd, length = struct.unpack_from("<II", thin, cursor)
        assert length >= 8
        if cmd == 0x19:
            va, vsize, fo, fsize = struct.unpack_from("<QQQQ", thin, cursor + 24)
            segments.append((va, fo, fsize))
        cursor += length
    previous = json.loads((HERE.parent / "offline-auth/identity-and-branch-checks.json").read_text())
    checks = []
    for check in previous["checks"]:
        address = int(check["address"], 16)
        matches = [(fo + address - va) for va, fo, fs in segments if va <= address and address + 4 <= va + fs]
        assert len(matches) == 1
        raw = thin[matches[0]:matches[0] + 4]
        instruction = int.from_bytes(raw, "little")
        assert instruction >> 26 == 0b100101
        imm = instruction & 0x3ffffff
        if imm & 0x2000000:
            imm -= 0x4000000
        target = hex(address + imm * 4)
        checks.append({"address": check["address"], "installed_file_offset": offset + matches[0],
                       "raw_bytes": raw.hex(), "decoded_bl_target": target,
                       "pass": raw.hex() == check["raw_bytes"] and target == check["decoded_bl_target"]})
    plist_bytes = (APP / "Contents/Info.plist").read_bytes()
    info = plistlib.loads(plist_bytes)
    result = {"kind": "ordinary-shell-and-file-observation", "installed_path": str(EXE),
              "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
              "bundle_identifier": info["CFBundleIdentifier"], "universal_sha256": sha(data),
              "info_plist_sha256": sha(plist_bytes), "arm64_sha256": sha(thin),
              "cached_matches_installed": thin == CACHE.read_bytes(),
              "matches_prior_arm64_sha256": sha(thin) == previous["arm64_sha256"], "checks": checks}
    for name, command in {"codesign": ["/usr/bin/codesign", "-dvv", str(APP)],
                          "entitlements": ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(APP)],
                          "os": ["/usr/bin/sw_vers"]}.items():
        run = subprocess.run(command, capture_output=True, text=True, check=True)
        result[name] = {"argv": command, "stdout": run.stdout, "stderr": run.stderr}
    print(json.dumps(result, indent=2))
    assert result["cached_matches_installed"] and result["matches_prior_arm64_sha256"]
    assert all(c["pass"] for c in checks)


if __name__ == "__main__":
    main()
