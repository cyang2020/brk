#!/bin/bash
# Build and bundle Brk with its own Chromium framework. ARCH may be arm64 or x86_64.
# BRK_CORE_DIR points to an extracted, matching engine artifact; local builds default to out/Brk.
# SKIP_TESTS=1 skips unit tests for iteration. CI sets BRK_VERSION and BRK_BUILD_NUMBER.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
HOST_ARCH="$(uname -m)"
ARCH="${ARCH:-$HOST_ARCH}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 2 ;; esac
PRODUCT="$(swift package dump-package | /usr/bin/python3 -I -c 'import json,sys; p=json.load(sys.stdin); print(next(x["name"] for x in p["products"] if "executable" in x["type"] and x["name"][0].isupper()))')"
BUNDLE_ID="dev.$(echo "$PRODUCT" | tr '[:upper:]' '[:lower:]').${PRODUCT}"
BRK_CORE_DIR="${BRK_CORE_DIR:-${BRK_CHROMIUM_ROOT:-$HOME/brk-chromium}/chromium/src/out/Brk}"
[ -f "$BRK_CORE_DIR/BrkCore.framework/BrkCore" ] || { echo "Missing BrkCore in $BRK_CORE_DIR; build engine/ or download the pinned engine artifact." >&2; exit 2; }
BUILD_ARGS=(-c "$CONFIG" --explicit-target-dependency-import-check error)
[ "$ARCH" = "$HOST_ARCH" ] || BUILD_ARGS+=(--triple "$ARCH-apple-macosx14.0")
swift build "${BUILD_ARGS[@]}"
if [ "$ARCH" = "$HOST_ARCH" ] && [ "${SKIP_TESTS:-0}" != 1 ]; then swift test; fi
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
python3 scripts/bundle-app.py --bin "$BIN" --core "$BRK_CORE_DIR" --arch "$ARCH" --product "$PRODUCT" --bundle-id "$BUNDLE_ID"
APP="dist/$PRODUCT.app"
# Add the app's resources and bundle declarations before signing.
cp Sources/BrkBase/Resources/website-rules.json "$APP/Contents/Resources/website-rules.json"
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
SIGN_IDENTITY=- scripts/sign-developer-id.sh "$APP"
echo "[build] $APP ($ARCH) signed ad hoc and verified"
