#!/bin/bash
# Writes an out directory's args.gn and runs gn gen. No compile.
#   engine/configure.sh                  # out/Brk from engine/args/brk.gn (development: fast relinks, no LTO)
#   engine/configure.sh release arm64    # out/BrkRelease-arm64 from engine/args/release.gn
#   engine/configure.sh release x64      # out/BrkRelease-x64, cross-built on Apple silicon (no Rosetta needed)
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BRK_SRC"
case "${1:-dev}" in
  dev)
    out="$BRK_OUT_BRK"
    mkdir -p "$out"
    cp "$ENGINE_DIR/args/brk.gn" "$out/args.gn" ;;
  release)
    cpu="${2:?usage: configure.sh release <arm64|x64>}"
    case "$cpu" in arm64) out="$BRK_OUT_RELEASE_ARM64" ;; x64) out="$BRK_OUT_RELEASE_X64" ;; *) echo "unknown cpu $cpu" >&2; exit 2 ;; esac
    # Official builds read Google's PGO profile for this branch and architecture; fetch it if it is not here yet (about 85 MB).
    target=$([ "$cpu" = arm64 ] && echo mac-arm || echo mac)
    python3 tools/update_pgo_profiles.py --target="$target" update --gs-url-base=chromium-optimization-profiles/pgo_profiles
    python3 v8/tools/builtins-pgo/download_profiles.py download --depot-tools "$BRK_DEPOT_TOOLS" --check-v8-revision
    mkdir -p "$out"
    { cat "$ENGINE_DIR/args/release.gn"; echo; echo "target_cpu = \"$cpu\""; } > "$out/args.gn" ;;
  *) echo "usage: configure.sh [dev | release <arm64|x64>]" >&2; exit 2 ;;
esac
gn gen "$out"
