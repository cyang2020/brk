#!/bin/bash
# Compiles a target at low priority, paused while anyone holds the native lock or memory is short (tools/paced-build.py).
# Never takes a /tmp/brk-*.lock. Run it detached:
#   nohup engine/build.sh chrome > /dev/null 2>&1 &
# Log: $BRK_LOGS/build-<out>-<target>-<stamp>.log. Rerunning continues where the last run stopped.
#   JOBS=4 engine/build.sh chrome      # fewer jobs when memory is short
#   BRK_OUT=out/BrkRelease-arm64 engine/build.sh chrome   # another out directory (engine/configure.sh release arm64)
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: build.sh <gn target>}"
jobs="${JOBS:-6}"
stamp="$(date +%Y%m%d-%H%M%S)"
outname="$(basename "$BRK_OUT")"
log="$BRK_LOGS/build-$outname-${target//[^A-Za-z0-9_-]/_}-$stamp.log"
cd "$BRK_SRC"
ln -sf "$log" "$BRK_LOGS/build-latest.log"
echo "[build] log: $log"
# One Chromium build at a time: a development build (out/Brk, minutes) makes every other out directory's build wait while it runs (their
# pause files exist); a long release build never makes a development build wait. BRK_PAUSE_OTHERS=0 or 1 overrides.
own_pause="$BRK_LOGS/pause-$outname"
others=()
pause_others="${BRK_PAUSE_OTHERS:-$([ "$outname" = "$(basename "$BRK_OUT_BRK")" ] && echo 1 || echo 0)}"
[ "$pause_others" = 1 ] && for dir in out/*/; do
  name="$(basename "$dir")"
  [ "$name" = "$outname" ] || [ -e "$BRK_LOGS/pause-$name" ] && continue
  others+=("$BRK_LOGS/pause-$name")
done
for file in ${others[@]+"${others[@]}"}; do echo "paused by build of $outname (pid $$)" > "$file"; done
trap 'rm -f ${others[@]+"${others[@]}"}' EXIT
python3 "$ENGINE_DIR/tools/paced-build.py" --log "$log" --pause-file "$own_pause" -- "$BRK_SRC/third_party/ninja/ninja" -C "$BRK_OUT" -j "$jobs" "$target"
tail -n 1 "$log"
