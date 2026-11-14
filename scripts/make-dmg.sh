#!/bin/bash
# Packs a built Brk.app into the disk image users download: opening it shows Brk next to an Applications folder
# over an arrow, and dragging one onto the other installs it. The release workflow runs it after the app is signed
# and notarized (docs/release.md); with SIGN_IDENTITY set, the image itself is signed too, so it can be notarized.
#
#   scripts/make-dmg.sh dist/Brk.app out/Brk-arm64.dmg
#   SIGN_IDENTITY="Developer ID Application: ..." [SIGN_KEYCHAIN=...] scripts/make-dmg.sh ...
#
# The window is laid out by dmgbuild (scripts/dmg/settings.py), which writes Finder's .DS_Store directly, so it
# needs no Finder and no AppleScript and works on a CI runner. dmgbuild and its two dependencies are installed into
# a throwaway virtual environment, pinned by hash (scripts/dmg/requirements.txt).
set -euo pipefail
APP="${1:?usage: make-dmg.sh <path to .app> <output .dmg>}"
OUT="${2:?usage: make-dmg.sh <path to .app> <output .dmg>}"
HERE="$(cd "$(dirname "$0")" && pwd)/dmg"
[ -d "$APP/Contents" ] || { echo "[dmg] $APP is not an app bundle" >&2; exit 1; }
PRODUCT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$APP/Contents/Info.plist" 2>/dev/null || basename "$APP" .app)"
ICON_FILE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true)"
ICON="$APP/Contents/Resources/${ICON_FILE%.icns}.icns"

WORK="$(mktemp -d)"
cleanup() {
  [ ! -d "$WORK/check" ] || hdiutil detach "$WORK/check" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT
# dmgbuild needs Python 3.10 or later; /usr/bin/python3 (Xcode's) is 3.9, so the one on PATH is used.
"${PYTHON:-python3}" -I -m venv "$WORK/venv"
"$WORK/venv/bin/python" -I -m pip install --quiet --disable-pip-version-check --no-deps --require-hashes \
  -r "$HERE/requirements.txt"

# One TIFF with both sizes, so Finder draws the sharp one on Retina screens.
tiffutil -cathidpicheck "$HERE/background.png" "$HERE/background@2x.png" -out "$WORK/background.tiff" 2>/dev/null

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
DEFINES=(-D "app=$APP" -D "background=$WORK/background.tiff")
[ -f "$ICON" ] && DEFINES+=(-D "icon=$ICON")
"$WORK/venv/bin/python" -I -m dmgbuild -s "$HERE/settings.py" "${DEFINES[@]}" "$PRODUCT" "$OUT"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  KEYCHAIN_ARGS=()
  [ -n "${SIGN_KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN")
  codesign --force --timestamp --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$OUT"
  codesign --verify --verbose "$OUT"
fi
hdiutil verify -quiet "$OUT"
mkdir "$WORK/check"
hdiutil attach -readonly -nobrowse -mountpoint "$WORK/check" "$OUT" >/dev/null
codesign --verify --deep --strict "$WORK/check/$(basename "$APP")"
hdiutil detach "$WORK/check" >/dev/null
rmdir "$WORK/check"
echo "[dmg] $OUT ($(du -h "$OUT" | cut -f1))"
