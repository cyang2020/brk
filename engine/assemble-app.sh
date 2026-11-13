#!/bin/bash
# Legacy entry point: the normal build now assembles BrkCore directly into dist/Brk.app.
set -euo pipefail
cd "$(dirname "$0")/.."
exec scripts/build.sh "$@"
