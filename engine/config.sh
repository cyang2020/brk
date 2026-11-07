# Shared settings for every engine/ script. Source it; do not run it.
# Everything Chromium lives outside the repo, under BRK_CHROMIUM_ROOT. No shell profile is touched: the scripts put
# depot_tools on PATH only for themselves.
set -euo pipefail

export BRK_CHROMIUM_ROOT="${BRK_CHROMIUM_ROOT:-$HOME/brk-chromium}"
export BRK_CHROMIUM_TAG="154.0.8037.98"
# The commit refs/tags/154.0.8037.98 pointed at when this was pinned; fetch.sh refuses a tag that moved.
export BRK_CHROMIUM_COMMIT="b859317bf11f6be47f9b7799ec690a0a42a1fb33"
export BRK_GCLIENT_DIR="$BRK_CHROMIUM_ROOT/chromium"
export BRK_SRC="$BRK_GCLIENT_DIR/src"
export BRK_DEPOT_TOOLS="$BRK_CHROMIUM_ROOT/depot_tools"
export BRK_LOGS="$BRK_CHROMIUM_ROOT/logs"
export BRK_BRANCH="brk/154.0.8037.98"
# Outputs: Vanilla proves the toolchain on unmodified source; Brk is the branch with the patch series applied.
export BRK_OUT_VANILLA="out/Vanilla"
export BRK_OUT_BRK="out/Brk"

export PATH="$BRK_DEPOT_TOOLS:$PATH"
# No usage reports from depot_tools or gclient.
export DEPOT_TOOLS_COLLECT_METRICS=0
export DEPOT_TOOLS_METRICS=0
# After the first bootstrap the depot_tools copy stays at the commit fetch.sh recorded.
export DEPOT_TOOLS_UPDATE="${DEPOT_TOOLS_UPDATE:-0}"
# No Google-internal SDK or toolchain downloads.
export DEPOT_TOOLS_WIN_TOOLCHAIN=0

mkdir -p "$BRK_LOGS"
