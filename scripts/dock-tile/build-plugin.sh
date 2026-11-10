#!/bin/bash
# Builds Brk's Dock tile plug-in (A131; scripts/dock-tile/BrkDockTilePlugIn.swift) into an app bundle and names it in
# the bundle's Info.plist (NSDockTilePlugIn), as Arc's DockTilePlugIn.plugin is. The caller signs the bundle after.
#
#   scripts/dock-tile/build-plugin.sh <path to .app>
#
# scripts/build.sh and scripts/station/refresh-app.sh run it. Idempotent.
set -euo pipefail
APP="${1:?usage: build-plugin.sh <path to .app>}"
cd "$(dirname "$0")/../.."
PLIST="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
HOST_ID="$("$PB" -c "Print :CFBundleIdentifier" "$PLIST")"
PLUGIN="$APP/Contents/PlugIns/BrkDockTile.plugin"
rm -rf "$PLUGIN"
mkdir -p "$PLUGIN/Contents/MacOS"
mkdir -p "$PLUGIN/Contents/Resources"
cp -R Sources/BrkSettings/Resources/AppIcons "$PLUGIN/Contents/Resources/"
swiftc -O -swift-version 5 -module-name BrkDockTile -emit-library -o "$PLUGIN/Contents/MacOS/BrkDockTile" \
  scripts/dock-tile/BrkDockTilePlugIn.swift Sources/BrkSettings/AppIconArt.swift
cat > "$PLUGIN/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>BrkDockTile</string>
  <key>CFBundleIdentifier</key><string>$HOST_ID.DockTilePlugIn</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>BrkDockTile</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSPrincipalClass</key><string>BrkDockTilePlugIn</string>
</dict>
</plist>
PLIST
"$PB" -c "Delete :NSDockTilePlugIn" "$PLIST" 2>/dev/null || true
"$PB" -c "Add :NSDockTilePlugIn string BrkDockTile.plugin" "$PLIST"
codesign --force --sign - "$PLUGIN"
echo "[dock-tile] $PLUGIN built for $HOST_ID"
