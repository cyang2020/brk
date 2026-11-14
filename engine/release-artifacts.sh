#!/bin/bash
# Build both official architectures in sequence and package the verified outputs.
# Usage: JOBS=4 engine/release-artifacts.sh <new-output-directory>
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
destination="${1:?usage: release-artifacts.sh <new-output-directory>}"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"
for cpu in arm64 x64; do
  "$ENGINE_DIR/incremental.py" --release "$cpu"
  arch="$cpu"; [ "$cpu" = x64 ] && arch=x86_64
  python3 "$ENGINE_DIR/package-artifact.py" --build "$BRK_SRC/out/BrkRelease-$cpu" --arch "$arch" --out "$destination" > "$destination/$arch.json"
  echo "Packaged $arch: $destination/$arch.json"
done
