<p align="center">
  <img src="docs/icon.png" width="96" height="96" alt="Verse icon">
</p>

<h1 align="center">Verse</h1>
<p align="center"><em>Verse — lyrics in a pill.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange?logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/license-MIT-e8b168" alt="MIT license">
</p>

Verse shows time-synced lyrics for whatever's playing, in a slim, draggable
glass pill that floats above every app — always on top, never in the way.
Click it and it unfurls into a translucent karaoke card. Calm when idle, tiny
when playing, beautiful when you want it. Works on every Mac (no notch
required).

**Website:** [cpt-nem0.github.io/verse](https://cpt-nem0.github.io/verse/)

## Install

### Homebrew

```sh
brew install --cask cpt-nem0/tap/verse
```

Verse is ad-hoc signed, not notarized by Apple, so Gatekeeper may still block
the first launch. If so, either re-run with `--no-quarantine`:

```sh
brew install --cask --no-quarantine cpt-nem0/tap/verse
```

or clear the flag afterwards (see Manual install below).

### One-line install

```sh
curl -fsSL https://raw.githubusercontent.com/cpt-nem0/verse/main/install.sh | bash
```

Downloads the latest release, installs it to `/Applications`, clears the
quarantine flag, and launches it.

### Manual

Download `Verse.zip` from [Releases](https://github.com/cpt-nem0/verse/releases/latest),
unzip it into `/Applications`, then run:

```sh
xattr -cr /Applications/Verse.app
```

This is necessary because Verse is ad-hoc signed rather than notarized by
Apple, so macOS Gatekeeper quarantines it on download and refuses to open it
("Verse is damaged and can't be opened") until the flag is cleared.

## Features

- **A ball when idle, a pill when singing.** No music → a 30pt translucent
  ball parked wherever you left it. Music playing → a capsule that hugs the
  current lyric line, spring-animated as it changes.
- **Click to unfurl.** One click opens a glass karaoke card: three lyric
  lines, click any line to seek, plus a scrubber and transport controls.
- **Four animation themes**, expressive → minimal: Type-on, Word spotlight,
  Light wipe (default), and Underline tracer — one setting drives both the
  pill and the popup.
- **Techie glass.** Translucent black material everywhere; the album's
  dominant color tints only the lyric text and popup content, never the
  material itself.
- **Edge-anchored growth.** The pill remembers which screen edge you parked it
  on and grows away from that edge as lines change width.
- **Zero setup.** Detects whatever's playing automatically — no linking
  accounts, no configuration.

## Supported sources

Spotify, Apple Music, YouTube Music (app or web), TIDAL, Deezer, Amazon
Music, Plexamp, VOX, Swinsian — plus web players in supported browsers when
the tab publishes real music metadata (artist and album, not just a video
title).

## How it works

Lyrics come from [LRCLIB](https://lrclib.net)'s free, open catalog, matched
on title/artist/album/duration and cached on disk so repeat plays render
offline. Now-playing data comes from the community
[`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) helper
(MediaRemote access has been restricted since macOS 15.4), with an
AppleScript polling fallback; a local playback clock interpolates between
updates so the animation stays smooth between polls.

## Building from source

Requirements: macOS 14+, Xcode command line tools, `cmake` (`brew install
cmake`), `git`.

```sh
chmod +x build.sh   # first time only
./build.sh run
```

The script clones and builds `mediaremote-adapter`, builds the Swift package
in release mode, and assembles + ad-hoc signs `build/Verse.app`. Other
commands: `./build.sh` (build only), `./build.sh install` (copy to
`/Applications`), `./build.sh clean`.

## Running checks

There's no XCTest target on this project; pure logic is covered by
self-contained checks:

```sh
swift run Verse --checks
```

Expect `ALL CHECKS PASSED`.

## Credits

- Lyrics from [LRCLIB](https://lrclib.net) — a free, open, crowd-sourced
  synced-lyrics database.
- Now-playing access via [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
  by [ungive](https://github.com/ungive) (BSD-3).

## License

MIT — see [LICENSE](LICENSE).
