#!/bin/bash
# Writes the Brk branch's commits over the pinned tag to engine/patches/ as a numbered series, replacing what was there.
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BRK_SRC"
rm -f "$ENGINE_DIR"/patches/*.patch
git format-patch --quiet --no-signature --zero-commit --full-index --abbrev=40 --output-directory "$ENGINE_DIR/patches" "$BRK_CHROMIUM_COMMIT..HEAD"
ls -1 "$ENGINE_DIR/patches"
