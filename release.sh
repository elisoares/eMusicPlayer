#!/bin/zsh
# Builds a universal "eMusic Player.app" and packs it into dist/eMusicPlayer.dmg
# (app + Applications shortcut for drag-to-install).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh --universal
rm -rf dist
mkdir -p dist/dmg
ditto "build.noindex/eMusic Player.app" "dist/dmg/eMusic Player.app"
ln -s /Applications dist/dmg/Applications
hdiutil create -quiet -volname "eMusic Player" -srcfolder dist/dmg -ov -format UDZO dist/eMusicPlayer.dmg
rm -rf dist/dmg
echo "Built $(pwd)/dist/eMusicPlayer.dmg"
