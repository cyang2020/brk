#!/bin/bash
# Puts Brk's AppleScript dictionary and Help pages into a built bundle and records where the build came from:
# - Resources/<Product>.sdef from Sources/BrkApp/Scripting/Brk.sdef, with NSAppleScriptEnabled and
#   OSAScriptingDefinition naming it (Cocoa scripting reads the dictionary from there; A133);
# - BrkGitCommit (the short commit) and BrkRepositoryURL (the origin remote as an https address) in Info.plist, for
#   Copy <Product> Info, Check for Updates… and Contact the Team;
# - Resources/Help/release-notes.html, Help > Release Notes: the build's first-parent history, newest first;
# - Resources/Help/credits.html, About's "other open source software": the CEF and CefSwift licences.
#
#   scripts/declare-scripting.sh <path to .app>
#
# scripts/build.sh and verify/visual-pairs/run-20261103/tools/refresh-app.sh run it before signing. Idempotent.
set -euo pipefail
APP="${1:?usage: declare-scripting.sh <path to .app>}"
cd "$(dirname "$0")/.."
PLIST="$APP/Contents/Info.plist"
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
git log --first-parent -n 300 --date=short --format='%ad%x09%h%x09%s' HEAD 2>/dev/null \
  | /usr/bin/python3 -I -c '
import html, sys
product, commit = sys.argv[1], sys.argv[2]
days = {}
for line in sys.stdin:
    parts = line.rstrip("\n").split("\t", 2)
    if len(parts) == 3: days.setdefault(parts[0], []).append((parts[1], parts[2]))
out = ["<!doctype html><html><head><meta charset=\"utf-8\"><title>%s Release Notes</title>" % html.escape(product),
       "<style>body{font:15px -apple-system,sans-serif;max-width:760px;margin:40px auto;padding:0 24px;color:#222}"
       "h1{font-size:28px}h2{font-size:16px;margin:28px 0 6px;color:#555}li{margin:4px 0}code{color:#888;font-size:12px}</style></head><body>",
       "<h1>%s Release Notes</h1><p>This build: <code>%s</code>. Each entry is a change merged into the branch it was built from, newest first.</p>" % (html.escape(product), html.escape(commit or "unknown"))]
for day, entries in days.items():
    out.append("<h2>%s</h2><ul>" % html.escape(day))
    out += ["<li>%s <code>%s</code></li>" % (html.escape(subject), html.escape(sha)) for sha, subject in entries]
    out.append("</ul>")
out.append("</body></html>")
print("\n".join(out))
' "$PRODUCT" "$COMMIT" > "$APP/Contents/Resources/Help/release-notes.html"
# About > "other open source software" (A129): the licences of what the bundle ships besides Chromium, whose own
# components are listed at chrome://credits (the About window's middle link).
CEF_LICENSE="$(ls .cef/dist/*/LICENSE.txt 2>/dev/null | head -1 || true)"
/usr/bin/python3 -I -c '
import html, pathlib, sys
product, cef_license, cefswift_license = sys.argv[1], sys.argv[2], sys.argv[3]
def text(path):
    try: return pathlib.Path(path).read_text()
    except OSError: return "(licence text not found in this checkout)"
parts = ["<!doctype html><html><head><meta charset=\"utf-8\"><title>%s Credits</title>" % html.escape(product),
         "<style>body{font:14px -apple-system,sans-serif;max-width:760px;margin:40px auto;padding:0 24px;color:#222}"
         "h1{font-size:26px}h2{font-size:17px;margin-top:32px}pre{white-space:pre-wrap;font-size:12px;background:#f5f5f5;padding:12px;border-radius:6px}</style></head><body>",
         "<h1>%s Credits</h1><p>%s is made possible by the Chromium open source project (its components are listed on the "
         "<code>chrome://credits</code> page) and the software below.</p>" % (html.escape(product), html.escape(product)),
         "<h2>Chromium Embedded Framework</h2><p>https://bitbucket.org/chromiumembedded/cef</p><pre>%s</pre>" % html.escape(text(cef_license)),
         "<h2>CefSwift</h2><p>Swift bindings for CEF, vendored in Vendor/CefSwift.</p><pre>%s</pre>" % html.escape(text(cefswift_license)),
         "</body></html>"]
print("\n".join(parts))
' "$PRODUCT" "${CEF_LICENSE:-/nonexistent}" Vendor/CefSwift/LICENSE > "$APP/Contents/Resources/Help/credits.html"
echo "[scripting] $APP: $PRODUCT.sdef, commit ${COMMIT:-none}, repository ${REPO:-none}, release notes, credits"
