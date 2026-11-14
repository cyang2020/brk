#!/usr/bin/env python3
"""Embed SwiftPM's complete universal Sparkle framework before app signing."""

import pathlib
import shutil
import subprocess
import sys


def framework_for(bin_dir: pathlib.Path) -> pathlib.Path:
    linked = bin_dir / "Sparkle.framework"
    if linked.exists():
        return linked.resolve()
    for parent in (bin_dir, *bin_dir.parents):
        artifacts = parent / "artifacts"
        if not artifacts.is_dir():
            continue
        candidates = sorted({path.resolve() for path in artifacts.rglob("Sparkle.framework")})
        if len(candidates) == 1:
            return candidates[0]
        if candidates:
            raise ValueError(f"ambiguous Sparkle artifacts under {artifacts}")
    raise ValueError(f"no SwiftPM Sparkle.framework found from {bin_dir}")


def embed(bin_dir: pathlib.Path, app: pathlib.Path) -> None:
    source = framework_for(bin_dir.resolve())
    for path in source.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(source):
            raise ValueError(f"Sparkle dependency symlink escapes the framework: {path}")
    for relative in ("Sparkle", "Autoupdate", "Updater.app", "XPCServices/Downloader.xpc", "XPCServices/Installer.xpc"):
        if not (source / relative).exists():
            raise ValueError(f"incomplete Sparkle framework: {relative}")
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(source / "Sparkle")], text=True).split()
    if not {"arm64", "x86_64"}.issubset(architectures):
        raise ValueError("Sparkle must support both arm64 and x86_64")
    destination = app / "Contents/Frameworks/Sparkle.framework"
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists():
        # ditto merges directories. Remove the old framework so stale helpers cannot survive a rebuild.
        shutil.rmtree(destination)
    subprocess.run(["/usr/bin/ditto", "--noqtn", str(source), str(destination)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(destination)], check=True)
    print(f"[bundle] embedded Sparkle.framework from {source}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: embed-sparkle.py <bin-dir> <app>")
    try:
        embed(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"[bundle] {error}")
