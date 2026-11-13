#!/bin/bash
# Runs the end-to-end scenarios on this Mac's display without the native lock, and writes REPORT.md, shots/ and logs/
# (each scenario's app stdout and stderr) to $E2E_OUT, by default ~/brk-evidence/e2e (outside the repository: run
# records are not committed, docs/testing-policy.md). For gate runs use scripts/run-native.py, which takes the lock.
#
#   scripts/e2e.sh                              # scripts/build.sh, then every scenario against dist/<Product>.app (BrkCore)
#   SKIP_BUILD=1 scripts/e2e.sh --only 2,4,R6   # reuse dist/<Product>.app
# Needs a logged-in GUI session (the app opens real windows). A locked display works: input is in-process NSEvents
# and the capture is by window id. The runner (Sources/BrkE2E) serves Tests/E2ESite on 127.0.0.1, launches the app
# once per scenario with its own BRK_DATA_DIR, drives it over the control socket, and quits it; a crash, a crash
# report or a non-zero exit at quit fails the scenario. Exit status 1 when any scenario failed.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"

[ "${SKIP_BUILD:-}" = "1" ] || scripts/build.sh
APP="dist/$PRODUCT.app"

OUT="${E2E_OUT:-$HOME/brk-evidence/e2e}"
mkdir -p "$OUT"
status=0
swift run -c "$CONFIG" brk-e2e --app "$APP" --site Tests/E2ESite --out "$OUT" "$@" || status=$?
echo "[e2e] report: $OUT/REPORT.md (exit $status)"
exit "$status"
