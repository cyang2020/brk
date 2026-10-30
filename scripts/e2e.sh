#!/bin/bash
# Runs the end-to-end scenarios on this Mac's display and writes verify/swift/REPORT.md, verify/swift/shots/ and
# verify/swift/logs/ (each scenario's app stdout and stderr).
#
#   scripts/e2e.sh                              # scripts/build.sh, then every scenario against dist/<Product>.app (CEF)
#   SKIP_BUILD=1 scripts/e2e.sh --only 2,4,R6   # reuse dist/<Product>.app
#   BRK_ENGINE=stub scripts/e2e.sh              # no Chromium: the SwiftPM-built executable with placeholder pages
#                                               # (built here, SKIP_BUILD or not, since `swift run` builds the runner
#                                               # anyway); scenarios that need Chromium report SKIPPED
#
# Needs a logged-in GUI session (the app opens real windows). A locked display works: input is in-process NSEvents
# and the capture is by window id. The runner (Sources/BrkE2E) serves Tests/E2ESite on 127.0.0.1, launches the app
# once per scenario with its own BRK_DATA_DIR, drives it over the control socket, and quits it; a crash, a crash
# report or a non-zero exit at quit fails the scenario. Exit status 1 when any scenario failed.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
ENGINE="${BRK_ENGINE:-cef}"
PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"

if [ "$ENGINE" = "stub" ]; then
  swift build -c "$CONFIG" --product "$PRODUCT"
  APP="$(swift build -c "$CONFIG" --show-bin-path)/$PRODUCT"
else
  [ "${SKIP_BUILD:-}" = "1" ] || scripts/build.sh
  APP="dist/$PRODUCT.app"
fi

mkdir -p verify/swift
status=0
swift run -c "$CONFIG" brk-e2e --app "$APP" --site Tests/E2ESite --out verify/swift --engine "$ENGINE" "$@" || status=$?
echo "[e2e] report: verify/swift/REPORT.md (exit $status)"
exit "$status"
