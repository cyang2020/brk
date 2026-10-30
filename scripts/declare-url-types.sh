#!/bin/bash
# Declares the app as a handler for http and https links in a bundle's Info.plist (CFBundleURLTypes), which macOS
# requires before `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` (Settings > General > "Set as Default
# Browser") can name the app, and which makes the GetURL Apple Event (BrkApp/ExternalLinks.swift) reach it.
#
#   scripts/declare-url-types.sh <path to Info.plist>
#
# The CEF plugin writes the Info.plist, so scripts/build.sh runs this after bundling and re-signs. Idempotent: the key
# is replaced whole, so a second run leaves the same file.
set -euo pipefail
PLIST="${1:?usage: declare-url-types.sh <Info.plist>}"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Delete :CFBundleURLTypes" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :CFBundleURLTypes array" "$PLIST"
i=0
for scheme in http https; do
  "$PB" -c "Add :CFBundleURLTypes:$i dict" \
        -c "Add :CFBundleURLTypes:$i:CFBundleURLName string $scheme" \
        -c "Add :CFBundleURLTypes:$i:CFBundleTypeRole string Viewer" \
        -c "Add :CFBundleURLTypes:$i:CFBundleURLSchemes array" \
        -c "Add :CFBundleURLTypes:$i:CFBundleURLSchemes:0 string $scheme" "$PLIST"
  i=$((i + 1))
done
echo "[url-types] $PLIST declares http and https"
