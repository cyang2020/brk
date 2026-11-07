#!/bin/bash
# Compiles a target at low priority, paused while anyone holds the native lock or memory is short (tools/paced-build.py).
# Never takes a /tmp/brk-*.lock. Run it detached:
#   nohup engine/build.sh chrome > /dev/null 2>&1 &
# Log: $BRK_LOGS/build-<target>-<stamp>.log. Rerunning continues where the last run stopped.
#   JOBS=4 engine/build.sh chrome      # fewer jobs when memory is short
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
target="${1:?usage: build.sh <gn target>}"
jobs="${JOBS:-6}"
stamp="$(date +%Y%m%d-%H%M%S)"
log="$BRK_LOGS/build-${target//[^A-Za-z0-9_-]/_}-$stamp.log"
cd "$BRK_SRC"
ln -sf "$log" "$BRK_LOGS/build-latest.log"
exec python3 "$ENGINE_DIR/tools/paced-build.py" --log "$log" -- "$BRK_SRC/third_party/ninja/ninja" -C "$BRK_OUT_BRK" -j "$jobs" "$target"
