#!/usr/bin/env python3
"""Check the standalone helper without launching or controlling any app."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[2] / "scripts/capture-arc-reference.swift"

PIXEL_CHECK = r'''
@main private struct PixelChecks {
    static func main() throws {
        let fixtures: [(String, [UInt8], Bool)] = [
            ("transparent", [UInt8](repeating: 0, count: 64), false),
            ("uniform", Array(repeating: [UInt8](arrayLiteral: 0, 0, 0, 255), count: 16).flatMap { $0 }, false),
            ("varied", (0..<16).flatMap { [UInt8($0 * 10), 0, 0, 255] }, true)
        ]
        for (name, bytes, shouldPass) in fixtures {
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            var accepted = true
            do { try validatePixels(image) } catch { accepted = false }
            guard accepted == shouldPass else { fatalError("Unexpected pixel result: \(name)") }
            print("\(name): \(accepted ? "accepted" : "rejected")")
        }
    }
}
'''

DEADLINE_CHECK = r'''
@main private struct DeadlineChecks {
    static func main() {
        let cancelled = CommandLine.arguments.dropFirst().first == "cancel"
        let deadline = CaptureDeadline(seconds: cancelled ? 1 : 0.05)
        if cancelled { deadline.cancel() }
        withExtendedLifetime(deadline) { Thread.sleep(forTimeInterval: cancelled ? 1.2 : 2) }
        print("deadline did not fire")
    }
}
'''


def main():
    executable = str(Path(sys.argv[1]).resolve())
    root = Path(tempfile.mkdtemp(prefix="arc-capture-checks.")).resolve()
    records = []

    def run(name, command, expected):
        completed = subprocess.run(command, capture_output=True, text=True, timeout=60)
        records.append({"name": name, "argv": command, "exit": completed.returncode,
                        "stdout": completed.stdout, "stderr": completed.stderr})
        assert completed.returncode == expected, name + "\n" + completed.stderr
        return completed

    try:
        run("help", [executable, "--help"], 0)
        run("missing_arguments", [executable], 1)
        run("duplicate_option", [executable, "--pid", "1", "--pid", "2"], 1)
        run("unknown_option", [executable, "--other", "x"], 1)
        output = root / "must-not-exist"
        run("non_arc_pid", [executable, "--pid", str(os.getpid()), "--window-id", "1", "--output", str(output)], 1)
        assert not output.exists()
        existing = root / "existing"
        existing.mkdir()
        marker = existing / "sentinel"
        marker.write_text("owned capture sentinel\n")
        run("existing_output", [executable, "--pid", str(os.getpid()), "--window-id", "1", "--output", str(existing)], 1)
        assert marker.read_text() == "owned capture sentinel\n"
        listing = json.loads(run("list", [executable, "--list"], 0).stdout)
        if listing["applications"]:
            pid = listing["applications"][0]["pid"]
            run("unavailable_window", [executable, "--pid", str(pid), "--window-id", "4294967295", "--output", str(output)], 1)
            assert not output.exists()
        source = SOURCE.read_text()
        assert source.count("@main private struct Main {") == 1
        fixture = root / "pixel-check.swift"
        fixture.write_text(source.split("@main private struct Main {")[0] + PIXEL_CHECK)
        binary = root / "pixel-check"
        run("compile_pixel_check", ["/usr/bin/xcrun", "swiftc", "-parse-as-library", str(fixture), "-o", str(binary)], 0)
        run("pixel_check", [str(binary)], 0)
        fixture.write_text(source.split("@main private struct Main {")[0] + DEADLINE_CHECK)
        run("compile_deadline_check", ["/usr/bin/xcrun", "swiftc", "-parse-as-library", str(fixture), "-o", str(binary)], 0)
        run("deadline_expires", [str(binary)], 124)
        run("deadline_cancelled", [str(binary), "cancel"], 0)
        result = {"kind": "ordinary-shell-observation", "sourceSHA256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                  "records": records, "non_arc_output_absent": not output.exists(), "existing_sentinel_unchanged": True,
                  "pixel_fixtures": "In-memory color data only; no reference image or UI was synthesized.",
                  "deadline_fixtures": "Owned helper-process lifetime checks only; Arc is not launched or signaled."}
    finally:
        shutil.rmtree(root)
    result["owned_test_root_removed"] = not root.exists()
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
