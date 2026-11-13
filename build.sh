#!/bin/zsh
# Builds MenuBarPlayer.app (menu bar only, no Dock icon) next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="MenuBarPlayer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/MenuBarPlayer" "$APP/Contents/MacOS/MenuBarPlayer"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MenuBarPlayer</string>
    <key>CFBundleIdentifier</key><string>local.menubarplayer</string>
    <key>CFBundleName</key><string>MenuBarPlayer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MenuBarPlayer controla o Spotify e o Apple Music para mostrar a faixa atual e tocar, pausar e pular músicas.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
