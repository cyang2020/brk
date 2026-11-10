#!/bin/bash
# The build station: one warm checkout that builds any fix branch incrementally and captures its Brk-side scenes.
#
#   ~/.t3/projects/brk/scripts/station/station.sh <branch-or-sha> <outdir> [scene list, e.g. P01,P02,P12 | all]
#
# Run it from the main checkout (the stations use this folder's capture script) with an absolute <outdir> outside the
# repository, e.g. ~/brk-evidence/<task>/station-branch; run it on main too and compare (docs/testing-policy.md).
#
# 1. Checks out the branch (detached) in one of the two station worktrees (~/.t3/worktrees/brk/station and
#    station2; the one with the shorter queue, or STATION=<path> to force one).
# 2. Builds under the shared build lock: a full scripts/build.sh the first time (no dist yet), afterwards only the
#    changed modules through refresh-app.sh (seconds to a minute or two instead of a cold build per worktree).
# 3. Runs capture-brk-scenes.py for the requested scenes into <outdir>.
# 4. Writes <outdir>/sheet.png (Arc | Brk | diff per pair, with the differing-pixel share) and <outdir>/sheet.tsv.
#
# The Arc 1.170 references are arc-reference/<scene>/ next to this script (ARC_RUN overrides). Needs the fixture site
# on 127.0.0.1:8764: python3 -m http.server 8764 --bind 127.0.0.1 --directory scripts/station/fixture-site (from the
# main checkout). Do not type while it captures.
set -euo pipefail
if [ "${STATION_LOCKED:-0}" != "1" ]; then
  # Two stations (worktrees station and station2), one user each at a time. Pick the one with the shorter queue
  # so one station can capture (little CPU) while the other compiles. STATION=<path> forces a station.
  WRAP="$HOME/.t3/projects/brk/scripts/with-batch-locks.py"
  a=0; b=0
  if [ -z "${STATION:-}" ]; then
    status="$(python3 "$WRAP" --status 2>/dev/null)"
    a=$(grep -c "brk-station.lock" <<<"$status" || true); b=$(grep -c "brk-station2.lock" <<<"$status" || true)
    if [ -d "$HOME/.t3/worktrees/brk/station2/dist/Brk.app" ] && [ "$b" -lt "$a" ]; then STATION="$HOME/.t3/worktrees/brk/station2"; else STATION="$HOME/.t3/worktrees/brk/station"; fi
  fi
  LOCK=/tmp/brk-station.lock; [ "$(basename "$STATION")" = station2 ] && LOCK=/tmp/brk-station2.lock
  echo "[station] using $(basename "$STATION") (queue: station $a, station2 $b)"
  exec env STATION_LOCKED=1 STATION="$STATION" python3 "$WRAP" --lock "$LOCK" -- "$0" "$@"
fi
REF="${1:?branch or sha}"; OUT="${2:?output directory}"; SCENES="${3:-all}"
STATION="${STATION:-$HOME/.t3/worktrees/brk/station}"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
ARC_RUN="${ARC_RUN:-$TOOLS/arc-reference}"
mkdir -p "$OUT"
cd "$STATION"
git checkout -q --detach "$REF"
SHA="$(git rev-parse --short HEAD)"
echo "[station] $REF at $SHA"
[ -e .cef ] || ln -s "$HOME/.cache/arc-spike-swift/.cef" .cef
if [ -d dist/Brk.app ]; then
  # incremental: the station lock already serializes station builds, and a warm incremental build is short,
  # so it does not queue behind the general build lock (cold builds and test runs still do)
  "$TOOLS/refresh-app.sh"
else
  python3 scripts/with-batch-locks.py --lock /tmp/brk-batch-build.lock -- env SKIP_TESTS=1 scripts/build.sh
fi
curl -sf -o /dev/null http://127.0.0.1:8764/home.html || { echo "[station] fixture site not answering on 8764; serve scripts/station/fixture-site there (see the top of this script)" >&2; exit 2; }
# the capture drives the real mouse and keyboard, so it must not overlap a native GUI test run
python3 scripts/with-batch-locks.py --lock /tmp/brk-core-native.lock -- \
  python3 "$TOOLS/capture-brk-scenes.py" dist/Brk.app "$OUT" --scenes "$SCENES" | tee "$OUT/capture.log"
# sheet: every brk png in OUT that has an arc partner in ARC_RUN
args=()
for f in "$OUT"/*-brk.png "$OUT"/*-brk-editor.png "$OUT"/*-brk-main.png; do
  [ -e "$f" ] || continue
  case "$f" in
    *-brk-editor.png) base="$(basename "$f" -brk-editor.png)"; arc="$ARC_RUN/${base%%-*}/$base-arc-editor.png"; label="$base-editor" ;;
    *-brk-main.png) base="$(basename "$f" -brk-main.png)"; arc="$ARC_RUN/${base%%-*}/$base-arc-main.png"; label="$base-main" ;;
    *) base="$(basename "$f" -brk.png)"; arc="$ARC_RUN/${base%%-*}/$base-arc.png"; label="$base" ;;
  esac
  [ -e "$arc" ] && args+=("$label" "$arc" "$f")
done
if [ ${#args[@]} -gt 0 ]; then
  ok=0
  for attempt in 1 2 3; do
    if "$TOOLS/bin/sheet" "$OUT/sheet.png" "${args[@]}" > "$OUT/sheet.tsv" 2>>"$OUT/sheet.err" && [ -s "$OUT/sheet.tsv" ]; then ok=1; break; fi
    echo "[station] sheet attempt $attempt failed (exit $?), retrying in 20 s" | tee -a "$OUT/sheet.err" >&2; sleep 20
  done
  [ "$ok" = 1 ] || echo "[station] sheet failed three times, see $OUT/sheet.err" >&2
  cat "$OUT/sheet.tsv"
else
  echo "[station] no Brk captures with an Arc partner in $OUT" >&2
fi
echo "[station] done: $OUT (built $SHA)"
