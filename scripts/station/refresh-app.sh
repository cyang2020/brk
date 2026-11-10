#!/bin/bash
# Rebuilds only the app and helper binaries and drops them into the existing dist/<Product>.app, then re-signs.
# This is the iteration build: it skips the CEF bundle assembly (copying the 132 MB framework and five helper
# apps) that scripts/build.sh does every time. A no-op rebuild takes a few seconds; a change in one module
# takes however long that module and its dependents take to compile.
#
#   python3 scripts/with-batch-locks.py --lock /tmp/brk-batch-build.lock -- scripts/station/refresh-app.sh
#
# Needs a dist/<Product>.app from one earlier scripts/build.sh run (the bundle, plist and resources come from there).
# Run from the package root. Not a delivery build: no unit tests, no plist regeneration.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
CONFIG="${CONFIG:-release}"
PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"
APP="dist/$PRODUCT.app"
[ -d "$APP" ] || { echo "[refresh] no $APP yet; run scripts/build.sh once first" >&2; exit 2; }
swift build -c "$CONFIG" --product "$PRODUCT" --explicit-target-dependency-import-check error
swift build -c "$CONFIG" --product cef-helper
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
cp "$BIN/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
for helper in "$APP/Contents/Frameworks/$PRODUCT Helper"*.app; do
  name="$(basename "$helper" .app)"
  cp "$BIN/cef-helper" "$helper/Contents/MacOS/$name"
done
cp Sources/BrkBase/Resources/website-rules.json "$APP/Contents/Resources/website-rules.json" 2>/dev/null || true
# the bundled media observer extension (its scripts are read at run time)
cp Sources/BrkCEF/AudibilityExtension/* "$APP/Contents/Resources/BrkAudibility/" 2>/dev/null || true
# the app icon, the same way scripts/build.sh makes it (branches without the icon script keep whatever the bundle has)
if [ -f scripts/app-icon/main.swift ] && [ -f Sources/BrkSettings/AppIconArt.swift ]; then
  ICONSET="$(mktemp -d)/$PRODUCT.iconset"
  if swiftc -O -o .build/brk-app-icon scripts/app-icon/main.swift Sources/BrkSettings/AppIconArt.swift 2>/dev/null \
     && .build/brk-app-icon "$ICONSET" original \
     && iconutil -c icns -o "$APP/Contents/Resources/$PRODUCT.icns" "$ICONSET"; then
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $PRODUCT" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    echo "[refresh] app icon written"
  else
    echo "[refresh] app icon step skipped (icon tool failed)" >&2
  fi
  rm -rf "$(dirname "$ICONSET")"
fi
# the AppleScript dictionary, the build's commit and the release notes (branches without the script keep the bundle's)
[ -x scripts/declare-scripting.sh ] && scripts/declare-scripting.sh "$APP"
# the Dock tile plug-in (branches without it keep whatever the bundle has)
[ -x scripts/dock-tile/build-plugin.sh ] && scripts/dock-tile/build-plugin.sh "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "[refresh] $APP refreshed from $BIN ($(git rev-parse --short HEAD))"
