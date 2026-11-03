#!/bin/bash
# Builds dist/<Product>.app: release build, CEF (pinned, SHA-1 checked) with five helper apps, ad-hoc signature.
# Notarization is out of scope.
#
#   scripts/build.sh            # release
#   CONFIG=debug scripts/build.sh
#   SKIP_TESTS=1 scripts/build.sh   # iteration build: compile, bundle and sign without the unit-test step
#
# Steps (each fails the script):
# 1. Read the product name from Package.swift (the only place it is written) via `swift package dump-package`.
# 2. swift build with the explicit target-dependency import check, so a module that imports something its
#    target does not declare fails here even if it compiled by accident.
# 3. swift test (the unit tests and ArchitectureTests run before anything is bundled).
# 4. `swift package cef bundle` (vendored CefSwift plugin): downloads CEF 154.0.34 minimal arm64 into .cef/ on first
#    use (132 MB, SHA-1 from Vendor/CefSwift/CEF_VERSION.json), builds the product and `cef-helper`, assembles
#    dist/<Product>.app with "<Product> Helper", "(Alerts)", "(GPU)", "(Plugin)", "(Renderer)", sets
#    LSEnvironment MallocNanoZone=0, signs ad hoc (--sign -).
# 5. scripts/declare-url-types.sh adds CFBundleURLTypes for http and https to the bundle's Info.plist (the plugin
#    writes the plist without them; the default-browser registration needs them). Device permission usage strings
#    are declared for the main app and all helpers before the bundle is signed again.
#    The app icon (A131): scripts/app-icon/main.swift draws Sources/BrkSettings/AppIconArt.swift's "The Original" into an
#    iconset, iconutil makes Resources/<Product>.icns and CFBundleIconFile names it, before the bundle is signed again.
# 6. codesign --verify --deep --strict.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"

PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"
BUNDLE_ID="dev.$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]').${PRODUCT}"
echo "[build] product $PRODUCT ($BUNDLE_ID), configuration $CONFIG"

swift build -c "$CONFIG" --explicit-target-dependency-import-check error
if [ "${SKIP_TESTS:-0}" = "1" ]; then
  echo "[build] SKIP_TESTS=1: unit tests not run; this bundle is for iteration, not delivery"
else
  swift test
fi

swift package --allow-writing-to-package-directory --allow-network-connections all \
  cef bundle --product "$PRODUCT" --configuration "$CONFIG" --bundle-id "$BUNDLE_ID" --sign -

APP="dist/$PRODUCT.app"
# 5. Declare http and https in the bundle (CFBundleURLTypes; F3) after the plugin wrote Info.plist, then sign again,
#    because the plugin signed before the edit.
mkdir -p "$APP/Contents/Resources/BrkAudibility"
cp Sources/BrkBase/Resources/website-rules.json "$APP/Contents/Resources/website-rules.json"
cp Sources/BrkCEF/AudibilityExtension/* "$APP/Contents/Resources/BrkAudibility/"
mkdir -p "$APP/Contents/Resources/BrkSounds"
cp Sources/BrkApp/SoundAssets/*.wav "$APP/Contents/Resources/BrkSounds/"
scripts/declare-url-types.sh "$APP/Contents/Info.plist"
ICONSET="$(mktemp -d)/$PRODUCT.iconset"
swiftc -O -o .build/brk-app-icon scripts/app-icon/main.swift Sources/BrkSettings/AppIconArt.swift
.build/brk-app-icon "$ICONSET" original
iconutil -c icns -o "$APP/Contents/Resources/$PRODUCT.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $PRODUCT" "$APP/Contents/Info.plist"
python3 scripts/declare-site-permissions.py "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "[build] $APP signed ad hoc and verified"
