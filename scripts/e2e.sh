#!/bin/bash
# Runs the end-to-end scenarios on this Mac's display and writes verify/swift/REPORT.md and verify/swift/shots/.
#
#   scripts/e2e.sh              # build, then every scenario
#   SKIP_BUILD=1 scripts/e2e.sh --only 2,4,R6
#
# Needs a logged-in GUI session (the app opens real windows). The runner (Sources/BrkE2E) starts the fixture server
# on Tests/E2ESite, launches dist/<Product>.app once per scenario with its own BRK_DATA_DIR, drives it over the
# control socket, and quits it; a crash report or non-zero exit at quit fails the scenario.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${SKIP_BUILD:-}" = "1" ] || scripts/build.sh
PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"
mkdir -p verify/swift/shots
swift run -c release brk-e2e --app "dist/$PRODUCT.app" --site Tests/E2ESite --out verify/swift "$@"
echo "[e2e] report: verify/swift/REPORT.md"
