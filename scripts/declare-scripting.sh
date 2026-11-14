#!/bin/bash
# Puts Brk's AppleScript dictionary and Help pages into a built bundle and records where the build came from:
# - Resources/<Product>.sdef from Sources/BrkApp/Scripting/Brk.sdef, with NSAppleScriptEnabled and
#   OSAScriptingDefinition naming it (Cocoa scripting reads the dictionary from there; A133);
# - BrkGitCommit (the short commit) and BrkRepositoryURL (the origin remote as an https address) in Info.plist, for
#   Copy <Product> Info, Check for Updates… and Contact the Team;
# - Resources/Help/release-notes.html, Help > Release Notes: curated version history from releases/*.md;
# - Resources/Help/credits.html, About's "other open source software": the Chromium and retained FindEditorScript licences.
#
#   scripts/declare-scripting.sh <path to .app>
#
# scripts/build.sh and scripts/station/refresh-app.sh run it before signing. Idempotent.
set -euo pipefail
APP="${1:?usage: declare-scripting.sh <path to .app>}"
cd "$(dirname "$0")/.."
PLIST="$APP/Contents/Info.plist"
VERSION="$(python3 scripts/release.py version)"
[ "${BRK_VERSION:-$VERSION}" = "$VERSION" ] || { echo 'BRK_VERSION must agree with VERSION' >&2; exit 1; }
python3 scripts/release.py validate --build "${BRK_BUILD_NUMBER:-1}" > /dev/null
PRODUCT="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$PLIST")"
PB=/usr/libexec/PlistBuddy
mkdir -p "$APP/Contents/Resources/Help"
cp Sources/BrkApp/Scripting/Brk.sdef "$APP/Contents/Resources/$PRODUCT.sdef"
"$PB" -c "Delete :NSAppleScriptEnabled" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :NSAppleScriptEnabled bool true" "$PLIST"
"$PB" -c "Delete :OSAScriptingDefinition" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :OSAScriptingDefinition string $PRODUCT.sdef" "$PLIST"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
"$PB" -c "Delete :BrkGitCommit" "$PLIST" 2>/dev/null || true
[ -n "$COMMIT" ] && "$PB" -c "Add :BrkGitCommit string $COMMIT" "$PLIST"
REMOTE="$(git remote get-url origin 2>/dev/null || true)"
case "$REMOTE" in
  git@*:*) HOST="${REMOTE#git@}"; REPO="https://${HOST%%:*}/${HOST#*:}" ;;
  https://*) REPO="$REMOTE" ;;
  *) REPO="" ;;
esac
REPO="${REPO%.git}"
"$PB" -c "Delete :BrkRepositoryURL" "$PLIST" 2>/dev/null || true
[ -n "$REPO" ] && "$PB" -c "Add :BrkRepositoryURL string $REPO" "$PLIST"
python3 scripts/release.py html --history > "$APP/Contents/Resources/Help/release-notes.html"
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
if [ -n "${BRK_BUILD_NUMBER:-}" ]; then
  "$PB" -c "Set :CFBundleVersion $BRK_BUILD_NUMBER" "$PLIST"
fi
# About > "other open source software" (A129): the licences of what the bundle ships besides Chromium, whose own
# components are listed at chrome://credits (the About window's middle link).
/usr/bin/python3 -I -c '
import html, pathlib, sys
product = sys.argv[1]
license = pathlib.Path("docs/licenses/FindEditorScript.txt").read_text()
print("<!doctype html><meta charset=\"utf-8\"><title>Credits</title>"
      "<style>body{font:14px -apple-system,sans-serif;max-width:760px;margin:40px auto}pre{white-space:pre-wrap}</style>"
      "<h1>" + html.escape(product) + " Credits</h1>"
      "<p>BrkCore is built from Chromium. Its components and licences are listed at <code>chrome://credits</code>.</p>"
      "<h2>Page find and editing script</h2><pre>" + html.escape(license) + "</pre>")
' "$PRODUCT" > "$APP/Contents/Resources/Help/credits.html"
echo "[scripting] $APP: $PRODUCT.sdef, commit ${COMMIT:-none}, repository ${REPO:-none}, release notes, credits"
