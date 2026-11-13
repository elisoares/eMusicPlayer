#!/bin/zsh
# Builds "eMusic Player.app" (menu bar only, no Dock icon) next to this script.
# --universal builds for Apple silicon and Intel (used by release.sh).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
if [[ "${1:-}" == "--universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/eMusicPlayer"
else
  swift build -c release
  BINARY=".build/release/eMusicPlayer"
fi
APP="eMusic Player.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate: swift Tools/make-icon.swift
cp "$BINARY" "$APP/Contents/MacOS/eMusicPlayer"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>eMusicPlayer</string>
    <key>CFBundleIdentifier</key><string>local.emusicplayer</string>
    <key>CFBundleName</key><string>eMusic Player</string>
    <key>CFBundleDisplayName</key><string>eMusic Player</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key>
    <string>O eMusic Player escuta o áudio do Spotify ou do Apple Music para desenhar o equalizador conforme a música.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>O eMusic Player controla o Spotify e o Apple Music para mostrar a faixa atual e tocar, pausar e pular músicas.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
