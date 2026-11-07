#!/bin/bash
# Makes dist-core/Brk.app: this checkout's dist/Brk.app plus BrkCore.framework, ad-hoc signed. CEF stays inside and stays the default; BRK_ENGINE=core
# picks the framework. Needs dist/Brk.app (scripts/build.sh, or refresh-app) and out/Brk/BrkCore.framework. Clones with APFS, so little extra disk.
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$ENGINE_DIR/.." && pwd)"
APP="$ROOT/dist-core/Brk.app"
rm -rf "$ROOT/dist-core"
mkdir -p "$ROOT/dist-core"
cp -cR "$ROOT/dist/Brk.app" "$APP"
cp -cR "$BRK_SRC/$BRK_OUT_BRK/BrkCore.framework" "$APP/Contents/Frameworks/BrkCore.framework"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" && echo "$APP"
