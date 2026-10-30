#!/usr/bin/env bash
# Run the e2e suite on Linux under Xvfb in the Playwright image. Safe to re-run.
# Results come back to verify/ (REPORT.md, shots/) and test-results/ (failure artifacts).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The image tag follows the locked Playwright version (v1.64.1 -> playwright:v1.64.1-noble).
IMAGE="mcr.microsoft.com/playwright:v$(node -p "require('$ROOT/package-lock.json').packages['node_modules/@playwright/test'].version")-noble"

# node_modules lives in a named volume, so the Linux Electron binary is cached between runs and
# never mixes with the host's (macOS) node_modules. The name carries a checksum of the lockfile:
# worktrees with different dependencies get separate volumes, and flock serialises the first install
# when two runs share one. Clean up old ones with: docker volume ls -q -f name=arc-e2e-node-modules | xargs docker volume rm
VOLUME="arc-e2e-node-modules-$(cksum < "$ROOT/package-lock.json" | cut -d' ' -f1)"

# The source is copied in rather than bind-mounted: Colima shares only $HOME by default, so a
# bind mount of a worktree under /tmp shows up in the container as an empty directory.
# verify/ is left out so a result can only come back if this run produced it.
cid=$(docker create --init --ipc=host -e FILTER="${1:-}" -w /work -v "$VOLUME:/work/node_modules" "$IMAGE" bash -euo pipefail -c '
  flock node_modules -c "[ -e node_modules/.installed ] || { npm ci && node node_modules/electron/install.js && touch node_modules/.installed; }"
  npm run build
  xvfb-run -a -s "-screen 0 1400x900x24" npm run e2e -- $FILTER
')
trap 'docker rm -f "$cid" >/dev/null' EXIT

COPYFILE_DISABLE=1 tar -C "$ROOT" -cf - \
  --exclude=./node_modules --exclude=./out --exclude=./.git --exclude=./.audit \
  --exclude=./verify --exclude=./test-results . | docker cp - "$cid:/work"

status=0
docker start -a "$cid" || status=$?

rm -rf "$ROOT/verify" "$ROOT/test-results"
docker cp "$cid:/work/verify" "$ROOT/verify" || echo "no verify/ produced" >&2
docker cp "$cid:/work/test-results" "$ROOT/test-results" 2>/dev/null || true
exit "$status"
