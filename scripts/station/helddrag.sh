#!/bin/zsh
# helddrag.sh <Arc|pid of a Brk> <out.png> <region x,y,w,h> x0 y0 x1 y1 [...]
# Presses at the first point (screen points), glides through the rest, screenshots the region while held at the last
# one, glides back slowly and releases at the press point (nothing is dropped). Refuses unless the process asked for
# is frontmost, and takes no screenshot when another process came to the front during the drag.
set -u
APP=$1; OUT=$2; REG=$3; shift 3
BIN="$(cd "$(dirname "$0")" && pwd)/bin"; T="${TMPDIR:-/tmp}/brk-helddrag.$$"; mkdir -p "$T"
"$BIN/key" clear >/dev/null 2>&1
if [ "$APP" = "Arc" ]; then osascript -e 'tell application "System Events" to tell process "Arc" to set frontmost to true' >/dev/null
else osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $APP) to true" >/dev/null; fi
sleep 0.4
# The frontmost process must be the one asked for: other tasks put their own Brk windows at the same frame as Arc's,
# and a drag meant for Arc landed in one of them on 2026-11-05.
front_ok() {
  if [ "$APP" = "Arc" ]; then [ "$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')" = "Arc" ]
  else [ "$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')" = "$APP" ]; fi
}
front_ok || { echo "the frontmost process is not $APP, not dragging"; exit 3; }
# ... and the window under the press point must be its own (another program's floating panel can sit over it).
TOP="$("$BIN/topwin" "$1" "$2")"
if [ "$APP" = "Arc" ]; then case "$TOP" in Arc\|*) ;; *) echo "the window at the press point belongs to $TOP, not dragging"; exit 3;; esac
else case "$TOP" in *\|"$APP"\|*) ;; *) echo "the window at the press point belongs to $TOP, not dragging"; exit 3;; esac; fi
"$BIN/pathdrag" 0.4 "$@" --signal "$T/sig" --release "$T/rel" --back >/dev/null &
for i in $(seq 1 400); do [ -f "$T/sig" ] && break; sleep 0.05; done
sleep 0.9
if front_ok; then screencapture -x -R"$REG" "$OUT"; RESULT="ok"; else RESULT="INVALID: another process came to the front during the drag, no screenshot"; fi
touch "$T/rel"; wait; sleep 0.8; rm -rf "$T"
echo "$(basename "$OUT") $RESULT"
