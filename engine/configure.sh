#!/bin/bash
# Writes out/Brk/args.gn from engine/args/brk.gn and runs gn gen. No compile.
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$BRK_SRC"
mkdir -p "$BRK_OUT_BRK"
cp "$ENGINE_DIR/args/brk.gn" "$BRK_OUT_BRK/args.gn"
gn gen "$BRK_OUT_BRK"
