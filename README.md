# Descript

A tiny native macOS menu-bar app that turns a YouTube link or a local MP4 into a clean
plain-text transcript on your clipboard in seconds. No browser, no cloud, no accounts —
MP4 transcription runs fully on-device.

## Features

- Lives in the menu bar (📜) — left-click opens the popup, right-click for Open/Quit
- YouTube mode: paste a URL (or use the Paste button), hit Extract — captions are fetched
  (manual tracks preferred over auto-generated, English preferred) and normalized to a
  single paragraph
- MP4 mode: pick a local .mp4 — audio is extracted and transcribed offline with Apple's
  on-device speech recognition (first use asks for Speech Recognition permission)
- Every successful transcript is copied to the clipboard automatically; Copy and Save
  buttons for the current text
- Notes scratchpad next to the transcript
- Per-source accent colors (Settings), persisted across launches

## Requirements

- macOS 13.0 or newer, Apple Silicon or Intel with the matching build
- Network access for YouTube mode; MP4 mode is fully offline

## Install

Grab `release/Descript-0.2.0.zip` (or the .dmg), unzip / mount, then drag
`Descript.app` to `/Applications` and launch it. The app is ad-hoc signed (no Apple
Developer ID): if macOS warns on first launch of a downloaded copy, right-click the app
and choose Open once.

## Build from source

```bash
./build.sh      # builds build/Descript.app + zip/dmg in release/
./verify.sh     # typecheck + build + live YouTube smoke (network)
```

`DESCRIPT_SMOKE_URL` overrides the smoke video; `DESCRIPT_SKIP_NETWORK=1` skips the
network smoke (offline development only).
