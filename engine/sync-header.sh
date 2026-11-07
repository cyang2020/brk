#!/bin/bash
# The one copy of the interface to edit is Sources/CBrkCore/include/BrkCore.h in this repo. The Chromium tree gets a copy that its
# own .gitignore keeps out of the patch series.
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$BRK_SRC/brk/public"
cmp -s "$ENGINE_DIR/../Sources/CBrkCore/include/BrkCore.h" "$BRK_SRC/brk/public/BrkCore.h" || cp "$ENGINE_DIR/../Sources/CBrkCore/include/BrkCore.h" "$BRK_SRC/brk/public/BrkCore.h"
