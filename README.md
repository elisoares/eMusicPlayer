# MenuBarPlayer

A small macOS menu bar app that shows and controls what is playing in Spotify or Apple Music.

- Album artwork, title, artist and album
- Previous / play-pause / next, seek bar and volume
- Switches automatically to whichever app starts playing
- No Dock icon; never launches the music app on its own

Requires macOS 13+ and Swift 5.10+.

## Build and install

```bash
./build.sh
ditto MenuBarPlayer.app /Applications/MenuBarPlayer.app
open /Applications/MenuBarPlayer.app
```

On first use macOS asks for permission to control Spotify / Music
(System Settings › Privacy & Security › Automation).
