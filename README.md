# vinyl

A turntable that lives on my Mac desktop. It sits behind every window as the wallpaper,
spins when Spotify or Apple Music is playing, shows the real album cover, and stacks the
covers of everything I've played beside it.

Personal project. Everything on screen is rendered live with SceneKit and every texture
(wood, grooves, lamp glass, placeholder sleeves) is drawn in code, so there are no image assets.

| Daylight | Lamplight | Top Down |
| --- | --- | --- |
| ![Daylight](docs/daylight.png) | ![Lamplight](docs/lamplight.png) | ![Top Down](docs/top-down.png) |

## What it does

- Three scenes: **Daylight**, **Lamplight** and **Top Down**
- Follows the clock: Daylight from 6:30 am, Lamplight after 6:30 pm (can be turned off)
- Click the tonearm (or the brass knob) on the desktop to play or pause
- A small printed card on the desk names the song and artist (can be turned off)
- Two brass buttons on the deck skip to the previous or next song
- The tonearm swings onto the record and the platter spins up at 33⅓ rpm
- Album covers come from Spotify and Apple Music, no login
- Each new song drops the previous cover onto the stack
- Transparent mode puts the turntable on your own wallpaper
- Menu bar icon for scenes, play/pause, settings and quit
- Stops rendering completely when nothing is playing

## Build and install

Needs Xcode command line tools (Swift 5.9+) and macOS 14 or later.

```bash
./scripts/build-app.sh --install
```

That builds `dist/Vinyl.app`, copies it to `/Applications` and launches it.

The first time it talks to Spotify or Music, macOS asks whether Vinyl may control that app.
Say yes: it is used to read the current track at launch and to play/pause on click.

## Development

Render a still of each scene without launching the app:

```bash
swift build -c release && .build/release/Vinyl --snapshot /tmp --art some-cover.png
```

While the app runs, `kill -USR1 $(pgrep -x Vinyl)` writes what the desktop currently shows
to `~/Library/Caches/com.abrj7.vinyl/live.png`.

## Layout

| File | What it holds |
| --- | --- |
| `Textures.swift` | Procedural textures and built-in artwork |
| `TurntableScene.swift` | The 3D scene, scene presets, spin and stack animation |
| `NowPlaying.swift` | Spotify / Apple Music playback monitor |
| `Artwork.swift` | Album cover lookup |
| `DesktopController.swift` | Wallpaper-level window, click handling, settings state |
| `AppDelegate.swift` | Menu bar item and wiring |
| `SettingsView.swift` | Settings window |
