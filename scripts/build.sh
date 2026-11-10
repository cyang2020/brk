#!/bin/bash
# Builds dist/<Product>.app: release build, CEF (pinned, SHA-1 checked) with five helper apps, ad-hoc signature.
# Notarization is out of scope.
#
#   scripts/build.sh            # release
#   CONFIG=debug scripts/build.sh
#   SKIP_TESTS=1 scripts/build.sh   # iteration build: compile, bundle and sign without the unit-test step
#   ARCH=x86_64 scripts/build.sh    # an Intel app, cross-compiled on Apple silicon (or ARCH=arm64 on an Intel Mac)
#   BRK_VERSION=1.2.0 BRK_BUILD_NUMBER=57 scripts/build.sh   # CFBundleShortVersionString and CFBundleVersion
#                                                           # (otherwise the plugin's 1.0 and 1; CI sets both)
#
# ARCH defaults to the machine's own (uname -m). For the other architecture the products are built with
# `swift build --triple <arch>-apple-macosx14.0`, handed to the plugin with --executable/--helper-executable (it only
# builds for the host) and bundled with that architecture's CEF (--platform macosx64 or macosarm64); the unit tests
# are skipped, since they cannot run on this machine. The Dock tile plug-in and the llama runtime follow the app's
# architecture. dist/<Product>.app is replaced either way.
#
# Steps (each fails the script):
# 1. Read the product name from Package.swift (the only place it is written) via `swift package dump-package`.
# 2. swift build with the explicit target-dependency import check, so a module that imports something its
#    target does not declare fails here even if it compiled by accident.
# 3. swift test (the unit tests and ArchitectureTests run before anything is bundled).
# 4. `swift package cef bundle` (vendored CefSwift plugin): downloads CEF 154.0.34 minimal for ARCH into .cef/ on first
#    use (132 MB arm64, 139 MB x86_64, SHA-1 from Vendor/CefSwift/CEF_VERSION.json), builds the product and `cef-helper`, assembles
#    dist/<Product>.app with "<Product> Helper", "(Alerts)", "(GPU)", "(Plugin)", "(Renderer)", sets
#    LSEnvironment MallocNanoZone=0, signs ad hoc (--sign -).
# 5. scripts/declare-url-types.sh adds CFBundleURLTypes for http and https to the bundle's Info.plist (the plugin
#    writes the plist without them; the default-browser registration needs them). Device permission usage strings
#    are declared for the main app and all helpers before the bundle is signed again.
#    The app icon: the approved artwork in Sources/BrkSettings/Resources/AppIcons is copied into the app.
#    scripts/app-icon/main.swift exports "The Original" into an iconset and iconutil writes Resources/<Product>.icns.
#    scripts/declare-scripting.sh adds the AppleScript dictionary, the build's commit and repository, the release
#    notes and credits pages (A133, A125, A129); scripts/dock-tile/build-plugin.sh adds the Dock tile plug-in that
#    shows the Icon pane's choice while Brk is not running (A131). scripts/add-llama-runtime.sh puts the pinned
#    llama.cpp runtime for the local models in Contents/Helpers/llama (Sources/BrkLocalModels).
# 6. codesign --verify --deep --strict.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
HOST_ARCH="$(uname -m)"
ARCH="${ARCH:-$HOST_ARCH}"
case "$ARCH" in
  arm64) CEF_PLATFORM=macosarm64 ;;
  x86_64) CEF_PLATFORM=macosx64 ;;
  *) echo "[build] ARCH=$ARCH: expected arm64 or x86_64" >&2; exit 2 ;;
esac

PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"
BUNDLE_ID="dev.$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]').${PRODUCT}"
echo "[build] product $PRODUCT ($BUNDLE_ID), configuration $CONFIG, $ARCH"

CEF_BUNDLE=(swift package --allow-writing-to-package-directory --allow-network-connections all
  cef bundle --product "$PRODUCT" --configuration "$CONFIG" --bundle-id "$BUNDLE_ID" --platform "$CEF_PLATFORM" --sign -)
if [ "$ARCH" = "$HOST_ARCH" ]; then
  swift build -c "$CONFIG" --explicit-target-dependency-import-check error
  if [ "${SKIP_TESTS:-0}" = "1" ]; then
    echo "[build] SKIP_TESTS=1: unit tests not run; this bundle is for iteration, not delivery"
  else
    swift test
  fi
  "${CEF_BUNDLE[@]}"
else
  TRIPLE="$ARCH-apple-macosx14.0"
  swift build -c "$CONFIG" --triple "$TRIPLE" --explicit-target-dependency-import-check error
  swift build -c "$CONFIG" --triple "$TRIPLE" --product cef-helper
  BIN="$(swift build -c "$CONFIG" --triple "$TRIPLE" --show-bin-path)"
  echo "[build] $ARCH is not this machine's architecture ($HOST_ARCH): unit tests not run (run them on $HOST_ARCH)"
  "${CEF_BUNDLE[@]}" --executable "$BIN/$PRODUCT" --helper-executable "$BIN/cef-helper"
fi

APP="dist/$PRODUCT.app"
# 5. Declare http and https in the bundle (CFBundleURLTypes; F3) after the plugin wrote Info.plist, then sign again,
#    because the plugin signed before the edit.
mkdir -p "$APP/Contents/Resources/BrkAudibility"
cp Sources/BrkBase/Resources/website-rules.json "$APP/Contents/Resources/website-rules.json"
cp Sources/BrkCEF/AudibilityExtension/* "$APP/Contents/Resources/BrkAudibility/"
mkdir -p "$APP/Contents/Resources/BrkSounds"
cp Sources/BrkApp/SoundAssets/*.wav "$APP/Contents/Resources/BrkSounds/"
cp -R Sources/BrkSettings/Resources/AppIcons "$APP/Contents/Resources/"
scripts/declare-url-types.sh "$APP/Contents/Info.plist"
ICONSET="$(mktemp -d)/$PRODUCT.iconset"
swiftc -O -o .build/brk-app-icon scripts/app-icon/main.swift Sources/BrkSettings/AppIconArt.swift
.build/brk-app-icon "$ICONSET" original "$PWD/Sources/BrkSettings/Resources/AppIcons"
iconutil -c icns -o "$APP/Contents/Resources/$PRODUCT.icns" "$ICONSET"
rm -rf "$(dirname "$ICONSET")"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $PRODUCT" "$APP/Contents/Info.plist"
python3 scripts/declare-site-permissions.py "$APP"
scripts/declare-scripting.sh "$APP"
scripts/dock-tile/build-plugin.sh "$APP"
scripts/add-llama-runtime.sh "$APP"
# The version CI stamps (docs/release.md): the main app and its five helpers carry the same numbers.
for plist in "$APP/Contents/Info.plist" "$APP"/Contents/Frameworks/*.app/Contents/Info.plist; do
  if [ -n "${BRK_VERSION:-}" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BRK_VERSION" "$plist"; fi
  if [ -n "${BRK_BUILD_NUMBER:-}" ]; then /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BRK_BUILD_NUMBER" "$plist"; fi
done
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "[build] $APP ($ARCH) signed ad hoc and verified"
