#!/bin/bash
# Re-signs a built app (scripts/build.sh signs ad hoc) with a Developer ID for distribution outside the App Store:
# hardened runtime and a secure timestamp on every piece of code, signed inside-out, because notarization rejects
# nested code signed only through `codesign --deep`. The release workflow runs it when the signing secrets are set
# (docs/release.md); scripts/notarize.sh comes after it.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/sign-developer-id.sh dist/Brk.app
#   SIGN_KEYCHAIN=/path/to/ci.keychain-db ...   # optional: look the identity up in this keychain only
#
# Order: loose Mach-O files (the BrkCore framework's libraries, the llama runtime in Contents/Helpers/llama), then
# frameworks, the Dock tile plug-in, the five helper apps and last the app itself.
# Entitlements, as Chromium's own Mac build (chrome/app/*-entitlements.plist) gives them:
# - the app: scripts/signing/app.entitlements (camera, microphone, location, Bluetooth, USB, printing, Photos);
#   under the hardened runtime macOS refuses these devices to a process signed without them;
# - "<Product> Helper (Renderer)", "(GPU)" and "(Plugin)": scripts/signing/helper-jit.entitlements (V8 and
#   SwiftShader generate code);
# - the plain helper, "(Alerts)", the libraries and the llama runtime: none.
set -euo pipefail
APP="${1:?usage: SIGN_IDENTITY=... sign-developer-id.sh <path to .app>}"
IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to a \"Developer ID Application: ...\" identity}"
SIGNING="$(cd "$(dirname "$0")" && pwd)/signing"
KEYCHAIN_ARGS=()
[ -n "${SIGN_KEYCHAIN:-}" ] && KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN")
PRODUCT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist")"

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$@"; }
# Deepest paths first, so whatever contains a file is signed after it.
by_depth() { /usr/bin/awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-; }
is_macho() { case "$(file -b "$1")" in Mach-O*) return 0 ;; *) return 1 ;; esac; }

# codesign treats every file in these folders as code; anything else there must move to Contents/Resources.
for folder in "$APP/Contents/MacOS" "$APP/Contents/Helpers"; do
  [ -d "$folder" ] || continue
  find "$folder" -type f | while IFS= read -r file; do
    if ! is_macho "$file"; then echo "[sign] $file is not code but sits in a code folder; move it to Contents/Resources" >&2; exit 1; fi
  done
done

# 1. Mach-O files that are not a bundle's own executable (those are sealed when their bundle is signed).
find "$APP/Contents" -type f | while IFS= read -r file; do
  case "$file" in
    *.app/Contents/MacOS/*|*.plugin/Contents/MacOS/*) continue ;;
    *.framework/Versions/*/*/*) ;;
    *.framework/Versions/*/*) continue ;;
  esac
  if is_macho "$file"; then echo "$file"; fi
done | by_depth | while IFS= read -r file; do sign "$file"; done

# 2. Nested bundles in one depth-ordered pass. Chromium's helpers live inside BrkCore.framework;
# signing the framework before those helpers would invalidate its seal.
find "$APP/Contents" -type d \( -name '*.framework' -o -name '*.plugin' -o -name '*.app' \) | by_depth \
  | while IFS= read -r bundle; do
    case "$(basename "$bundle")" in
      *' (Renderer).app'|*' (GPU).app'|*' (Aperitif Renderer).app'|*' (Aperitif GPU).app')
        sign --entitlements "$SIGNING/helper-jit.entitlements" "$bundle" ;;
      *) sign "$bundle" ;;
    esac
  done

# 4. The app.
sign --entitlements "$SIGNING/app.entitlements" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
# Every piece of code must carry the hardened runtime, or notarization refuses the whole app.
find "$APP/Contents" -type f | while IFS= read -r file; do
  is_macho "$file" || continue
  details="$(codesign -dv "$file" 2>&1)"
  case "$details" in *flags=*runtime*) ;; *) echo "[sign] $file has no hardened runtime" >&2; exit 1 ;; esac
done
echo "[sign] $APP signed with \"$IDENTITY\", hardened runtime, timestamped"
