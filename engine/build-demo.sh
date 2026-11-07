#!/bin/bash
# Compiles engine/demo/main.swift and bundles it with the built framework: $BRK_CHROMIUM_ROOT/demo/BrkCoreDemo.app. The framework is an APFS
# clone, so this takes no extra disk. Needs out/Brk/BrkCore.framework (engine/build.sh chrome).
source "$(dirname "$0")/config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$BRK_CHROMIUM_ROOT/demo/BrkCoreDemo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$ENGINE_DIR/demo/Info.plist" "$APP/Contents/Info.plist"
cp -cR "$BRK_SRC/$BRK_OUT_BRK/BrkCore.framework" "$APP/Contents/Frameworks/BrkCore.framework"
swiftc -swift-version 6 -import-objc-header "$ENGINE_DIR/../Sources/CBrkCore/include/BrkCore.h" \
  -framework AppKit -o "$APP/Contents/MacOS/BrkCoreDemo" "$ENGINE_DIR/demo/main.swift" 2>&1 | grep -v '^$' || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
ls -la "$APP/Contents/MacOS/BrkCoreDemo"
