#!/bin/bash
# Makes the Brk branch in the Chromium tree: starts at the pinned tag, applies engine/patches/*.patch in order, then copies the
# one interface header from the repo. Refuses to run over uncommitted changes. To keep working on an existing branch use
# engine/export-patches.sh instead of running this.
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BRK_SRC"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "uncommitted changes in $BRK_SRC" >&2
  exit 1
fi
git checkout -B "$BRK_BRANCH" "$BRK_CHROMIUM_COMMIT"
shopt -s nullglob
patches=("$ENGINE_DIR"/patches/*.patch)
if [ "${#patches[@]}" -gt 0 ]; then
  git -c user.name="Brk Engine" -c user.email="brk-engine@localhost" am -3 --keep-cr --committer-date-is-author-date "${patches[@]}"
fi
"$ENGINE_DIR/sync-header.sh"
gclient runhooks --force >/dev/null 2>&1 || true
echo "[apply] $BRK_BRANCH at $(git rev-parse --short HEAD), ${#patches[@]} patches"
