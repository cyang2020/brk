#!/bin/bash
# Updates an out directory's configuration only when its arguments change. No compile.
#   engine/configure.sh                  # out/Brk from engine/args/brk.gn (development: fast relinks, no LTO)
#   engine/configure.sh release arm64    # out/BrkRelease-arm64 from engine/args/release.gn
#   engine/configure.sh release x64      # out/BrkRelease-x64, cross-built on Apple silicon (no Rosetta needed)
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BRK_SRC"
force=0
if [ "${1:-}" = --force ]; then force=1; shift; fi
case "${1:-dev}" in
  dev)
    out="$BRK_OUT_BRK"
    preset="$ENGINE_DIR/args/brk.gn"
    cpu="" ;;
  release)
    cpu="${2:?usage: configure.sh release <arm64|x64>}"
    case "$cpu" in arm64) out="$BRK_OUT_RELEASE_ARM64" ;; x64) out="$BRK_OUT_RELEASE_X64" ;; *) echo "unknown cpu $cpu" >&2; exit 2 ;; esac
    preset="$ENGINE_DIR/args/release.gn" ;;
  *) echo "usage: configure.sh [--force] [dev | release <arm64|x64>]" >&2; exit 2 ;;
esac
mkdir -p "$out"
candidate="$(mktemp "$out/.brk-args.XXXXXX")"
trap 'rm -f "$candidate" "$candidate.next" "$candidate.profiles"' EXIT
cat "$preset" > "$candidate"
if [ -n "$cpu" ]; then printf '\ntarget_cpu = "%s"\n' "$cpu" >> "$candidate"; fi
: > "$candidate.profiles"
if [ -n "$cpu" ]; then
  pgo_target=$([ "$cpu" = arm64 ] && echo mac-arm || echo mac)
  for input in "chrome/build/$pgo_target.pgo.txt" tools/update_pgo_profiles.py v8/tools/builtins-pgo/download_profiles.py; do
    if [ -f "$input" ]; then shasum -a 256 "$input" >> "$candidate.profiles"; fi
  done
  if [ -e v8/.git ]; then git -C v8 rev-parse HEAD >> "$candidate.profiles"; fi
fi
if [ "$force" = 0 ] && [ -f "$out/build.ninja" ] &&
   cmp -s "$candidate" "$out/args.gn" && cmp -s "$candidate" "$out/.brk-configured-args.gn" &&
   cmp -s "$candidate.profiles" "$out/.brk-configured-profile-inputs"; then
  echo "[configure] $out unchanged; reusing its configuration and compiled objects"
  exit 0
fi
if [ "$force" = 1 ]; then reason="forced regeneration"
elif [ ! -f "$out/build.ninja" ]; then reason="missing build manifest"
elif ! cmp -s "$candidate" "$out/args.gn"; then reason="build arguments changed"
elif ! cmp -s "$candidate.profiles" "$out/.brk-configured-profile-inputs"; then reason="profile inputs changed or unrecorded"
else reason="configuration initialization or retry"; fi
echo "[configure] $out: $reason; keeping compiled objects"
if [ -n "$cpu" ]; then
    # Official builds read Google's PGO profile for this branch and architecture; fetch it if it is not here yet (about 85 MB).
    python3 tools/update_pgo_profiles.py --target="$pgo_target" update --gs-url-base=chromium-optimization-profiles/pgo_profiles
    python3 v8/tools/builtins-pgo/download_profiles.py download --depot-tools "$BRK_DEPOT_TOOLS" --check-v8-revision
fi
if ! cmp -s "$candidate" "$out/args.gn"; then
  cp "$candidate" "$candidate.next"
  mv "$candidate.next" "$out/args.gn"
fi
gn gen "$out"
mv "$candidate" "$out/.brk-configured-args.gn"
mv "$candidate.profiles" "$out/.brk-configured-profile-inputs"
