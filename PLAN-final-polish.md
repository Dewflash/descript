# PLAN-final-polish — self-verified 0.2.0 release

- **Rank:** 5 of 5 — MUST RUN LAST
- **Dependencies:** after PLAN-verify-script, PLAN-youtube-fallback, PLAN-popup-persistence,
  PLAN-launch-at-login (or their honest BLOCKERS.md entries).
- **Effort:** Large (~2 h, most of it the manual QA run)
- **Files touched:** `Info.plist`, `build.sh`, `README.md`, `RELEASE-QA.md` (new),
  `python-build/` (deleted from git). Nothing else.

## Goal

Turn "it builds on my machine" into a release someone can trust without any human vetting
it afterwards: dead prototype removed, bundle actually codesigned, version single-sourced
and bumped, README describing only shipped behavior, and a ~20-row manual QA pass executed
against the REAL packaged artifact with a recorded SHIP / DO-NOT-SHIP verdict.

## Steps

1. **Remove the dead Python prototype** (superseded by the native app; git history
   preserves it):

```bash
git rm -r python-build
```

2. **Info.plist** — four edits:
   - `CFBundleShortVersionString`: `0.1.0` → `0.2.0`
   - `CFBundleVersion`: `1` → `2`
   - Add, directly BEFORE the `LSMinimumSystemVersion` key (keys stay alphabetical):

```xml
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
```

   - Add, directly BEFORE the `NSMicrophoneUsageDescription` key:

```xml
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Dewflash. All rights reserved.</string>
```

   (This file is indented with tabs — match it.)

3. **build.sh — single-source the version.** Replace lines 7–13
   (`APP_NAME=…` through `DMG_PATH=…`) with:

```bash
APP_NAME="Descript"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
BUILD_DIR="build"
RELEASE_DIR="release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/${APP_NAME}"
ZIP_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.zip"
DMG_PATH="${RELEASE_DIR}/${APP_NAME}-${VERSION}.dmg"
```

4. **build.sh — sign the bundle.** Directly after the line
   `chmod +x "${EXECUTABLE_PATH}"` and BEFORE the `rm -f "${ZIP_PATH}" "${DMG_PATH}"`
   packaging block, insert:

```bash
codesign --force --sign - --identifier com.dewflash.descript "${APP_PATH}"
codesign --verify --strict "${APP_PATH}"
```

5. **README.md — full replacement.** FIRST read `BLOCKERS.md` if it exists: any feature
   whose plan was reverted/blocked must NOT appear below (delete its bullet and its QA
   row). Assuming all plans landed, replace the entire file with:

```markdown
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
- Launch-at-login toggle (Settings)

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
```

6. **Build the release artifacts:** run `./verify.sh` (it runs `build.sh`, which now signs
   and names artifacts `Descript-0.2.0.*`). Confirm `release/Descript-0.2.0.zip` and
   `release/Descript-0.2.0.dmg` exist.

7. **Install the PACKAGED artifact for QA** (never QA the dev build in `build/`):

```bash
rm -rf /tmp/descript-qa && mkdir -p /tmp/descript-qa
ditto -x -k release/Descript-0.2.0.zip /tmp/descript-qa
rm -rf /Applications/Descript.app
cp -R /tmp/descript-qa/Descript.app /Applications/
open /Applications/Descript.app
```

   Before launching: quit any already-running Descript (right-click its 📜 → Quit
   Descript), or you'll have two icons and QA results will lie to you.

8. **Run the QA checklist** — create `RELEASE-QA.md` with EXACTLY the template below, then
   perform every row against `/Applications/Descript.app` and fill Result
   (PASS / FAIL / BLOCKED / N/A) + Notes. The rule, verbatim, stays in the file:
   "PASS only from actually performing the check — an honest FAIL committed is worth more
   than a green lie."

```markdown
# RELEASE-QA — Descript 0.2.0

Artifact under test: `release/Descript-0.2.0.zip`, unzipped and installed to
`/Applications/Descript.app` (the packaged artifact, NOT the dev build).
Date: <fill>  ·  macOS: <fill `sw_vers -productVersion`>  ·  Tester: executor

**PASS only from actually performing the check — an honest FAIL committed is worth more
than a green lie.**

| # | Area | Check | Pass condition | Result | Notes |
|---|------|-------|----------------|--------|-------|
| 1 | Install | Unzip release zip, copy to /Applications, launch | 📜 appears in menu bar, no crash, no Dock icon | | |
| 2 | Identity | Finder Get Info on /Applications/Descript.app | Custom scroll icon shown; Version reads 0.2.0 | | |
| 3 | Signing | `codesign --verify --strict /Applications/Descript.app` | exit 0 | | |
| 4 | Popup | Left-click menu bar icon | Popup opens anchored to icon; left-click again closes | | |
| 5 | Popup | Click anywhere outside the open popup | Popup dismisses (transient) | | |
| 6 | Menu | Right-click menu bar icon | Menu shows "Open Descript" and "Quit Descript"; Open opens popup | | |
| 7 | YouTube | Paste a known-captioned URL, press Extract | Transcript text appears; status "YouTube · N words", N > 0 | | |
| 8 | YouTube | Immediately paste into TextEdit | Clipboard holds the transcript that was just extracted | | |
| 9 | YouTube | Paste button with a URL on the clipboard | URL field fills from clipboard | | |
| 10 | YouTube | Extract with input `not a url` | Warning alert with clear message; popup returns after dismiss; status "YouTube · failed" | | |
| 11 | YouTube | Extract a captionless or unavailable video | Error alert states a reason (no hang, no beachball) | | |
| 12 | MP4 | Choose MP4 → select an .mp4 containing English speech | Popup re-presents itself showing "MP4 · transcribing", then transcript + word count; clipboard updated. First run: Speech Recognition permission prompt appears — approve it | | |
| 13 | MP4 | Choose MP4 → Cancel in the picker | Popup returns; status unchanged; no error | | |
| 14 | Transcript | Copy button | Clipboard equals the transcript pane text | | |
| 15 | Transcript | Save button → save to a temp folder | .txt file written whose contents equal the pane; popup returns | | |
| 16 | Transcript | Save button → Cancel | No file written; popup returns | | |
| 17 | Notes | Type in Notes, close popup, reopen | Notes text still there (within the same run) | | |
| 18 | Settings | Change YouTube accent color | Extract/Settings buttons recolor immediately; still applied after quit + relaunch | | |
| 19 | Settings | Launch at Login ON | Descript listed in System Settings > General > Login Items & Extensions; toggle OFF removes it | | |
| 20 | Lifecycle | Right-click → Quit Descript | Icon disappears; process gone (`pgrep -x Descript` empty) | | |
| 21 | Resilience | Turn Wi-Fi off, Extract a YouTube URL | Clear error alert, app stays responsive; Wi-Fi back on, same URL succeeds | | |

## Verdict

**SHIP / DO-NOT-SHIP** (delete one)

Justification: <one paragraph. Any FAIL on rows 1, 3, 7, 8, 12, or 20 forces DO-NOT-SHIP.
BLOCKED rows (e.g., no speech MP4 available) must say why and are only acceptable outside
that forcing set.>
```

9. **Verdict and tag.** Commit everything (including the filled `RELEASE-QA.md`). Then,
   ONLY if the verdict is SHIP:

```bash
git tag v0.2.0
```

   Do NOT push (no `git push`, no `git push --tags`) — pushing is Kevin's call.

## Edge cases a weaker model would miss

- **Signing order is load-bearing.** `codesign` seals the bundle contents; ANY file copied
  into `Descript.app` after signing invalidates the seal and `codesign --verify` fails.
  Sign after the last `cp` into the bundle and the `chmod`, before `ditto`/`hdiutil`
  package it. If you ever reorder build.sh, re-check this.
- **`--sign -` is ad-hoc signing.** There is no Apple Developer ID on this machine. Do NOT
  attempt `--sign "Developer ID Application: …"`, do not run `xcrun notarytool`, do not
  add `--options runtime` (hardened runtime without a real identity can break Speech/TCC
  behavior). If `codesign --verify --strict` fails: STOP and report — do not improvise.
- **PlistBuddy lives at `/usr/libexec/PlistBuddy`** — it is not on PATH; the full path in
  the script is intentional.
- **QA runs against the unzipped release artifact, not `build/Descript.app`.** The zip
  round-trip (`ditto --norsrc --noextattr`) is what users receive — it can drop xattrs and
  is exactly where a broken executable bit or lost icon would surface. Testing the dev
  build proves nothing about the artifact.
- **A locally built zip has no quarantine xattr,** so Gatekeeper's "downloaded from the
  internet" first-launch warning cannot be tested here. Row 1 tests launch, not
  Gatekeeper. The README's right-click-Open note covers real downloads; do not delete it
  because "it launched fine for me".
- **Row 12 needs a real .mp4 with English speech.** If none exists on the machine, mark it
  BLOCKED with a note — never PASS untested. (BLOCKED on row 12 forces DO-NOT-SHIP since
  it's in the forcing set; that is the honest outcome.)
- **Row 19 must be tested from `/Applications`** — `SMAppService` registers the current
  bundle path (see PLAN-launch-at-login edge cases); testing from `build/` then moving the
  app would record a stale login item and a false result. If PLAN-launch-at-login was
  blocked, mark row 19 N/A and delete the launch-at-login bullets from README (step 5's
  BLOCKERS rule).
- **Old `Descript-0.1.0.*` artifacts remain in `release/`.** That's fine — `release/` is
  gitignored. Do not commit artifacts, do not "clean up" by committing deletions of
  ignored files (there is nothing to commit).
- **`git rm -r python-build` only touches the repo.** The sibling directories
  `../../python/` and `../../outputs/` are stale exports OUTSIDE this repository — do not
  touch them (AGENTS.md house rule).
- **The tag is conditional.** DO-NOT-SHIP with a committed honest QA file and no tag is a
  successful outcome of this plan. Tagging anyway is the one unforgivable move.

## Acceptance criteria

1. `./verify.sh; echo "exit=$?"` → `VERIFY OK`, `exit=0`.
2. `codesign --verify --strict build/Descript.app && echo signed` → `signed`.
3. `ls release/Descript-0.2.0.zip release/Descript-0.2.0.dmg` → both listed.
4. `git ls-files python-build` → empty output.
5. `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist` → `0.2.0`.
6. `! grep -q "wiring pass" README.md && echo clean` → prints `clean` (the old
   prototype-era README language is gone).
7. `RELEASE-QA.md` is committed, every row has a Result, and the Verdict line reads exactly
   SHIP or DO-NOT-SHIP with a justification.
8. `git tag -l v0.2.0` → prints `v0.2.0` if and only if the verdict is SHIP.
9. `git status --porcelain` after commit → empty.

Suggested commit message:

    release: v0.2.0 — signed bundle, versioned packaging, README, QA verdict
