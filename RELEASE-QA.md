# RELEASE-QA — Descript 0.2.0

Artifact under test: `release/Descript-0.2.0.zip`, unzipped and installed to
`/Applications/Descript.app` (the packaged artifact, NOT the dev build).
Date: 2026-07-11  ·  macOS: 26.5.1  ·  Tester: executor

**PASS only from actually performing the check — an honest FAIL committed is worth more
than a green lie.**

| # | Area | Check | Pass condition | Result | Notes |
|---|------|-------|----------------|--------|-------|
| 1 | Install | Unzip release zip, copy to /Applications, launch | 📜 appears in menu bar, no crash, no Dock icon | BLOCKED | Zip was unzipped, copied to `/Applications`, and the app process launched as PID 6006; menu bar/Dock visual verification blocked because `osascript` lacks assistive access and `screencapture` cannot create a display image. |
| 2 | Identity | Finder Get Info on /Applications/Descript.app | Custom scroll icon shown; Version reads 0.2.0 | BLOCKED | `Info.plist` reports 0.2.0 and `DescriptIcon.icns` exists in the installed bundle; Finder Get Info visual check blocked by missing UI automation/screen capture. |
| 3 | Signing | `codesign --verify --strict /Applications/Descript.app` | exit 0 | PASS | Command exited 0 and printed `signed-applications`. |
| 4 | Popup | Left-click menu bar icon | Popup opens anchored to icon; left-click again closes | BLOCKED | Cannot click or inspect the menu bar item: System Events reports `osascript is not allowed assistive access. (-1728)`. |
| 5 | Popup | Click anywhere outside the open popup | Popup dismisses (transient) | BLOCKED | Requires GUI interaction/visual confirmation; blocked by denied assistive access and unavailable screenshot capture. |
| 6 | Menu | Right-click menu bar icon | Menu shows "Open Descript" and "Quit Descript"; Open opens popup | BLOCKED | Requires right-clicking the status item; blocked by denied assistive access. |
| 7 | YouTube | Paste a known-captioned URL, press Extract | Transcript text appears; status "YouTube · N words", N > 0 | BLOCKED | Service-level smoke passed in `./verify.sh` with `OK words=5199`; packaged UI flow could not be performed without assistive access. |
| 8 | YouTube | Immediately paste into TextEdit | Clipboard holds the transcript that was just extracted | BLOCKED | Depends on row 7 packaged UI extraction and TextEdit interaction; UI automation blocked. |
| 9 | YouTube | Paste button with a URL on the clipboard | URL field fills from clipboard | BLOCKED | Requires popup interaction; assistive access denied. |
| 10 | YouTube | Extract with input `not a url` | Warning alert with clear message; popup returns after dismiss; status "YouTube · failed" | BLOCKED | The popup-return behavior is not shipped because `PLAN-popup-persistence.md` is blocked in `BLOCKERS.md`; alert UI also could not be driven without assistive access. |
| 11 | YouTube | Extract a captionless or unavailable video | Error alert states a reason (no hang, no beachball) | BLOCKED | Requires packaged UI interaction; assistive access denied. |
| 12 | MP4 | Choose MP4 → select an .mp4 containing English speech | Popup re-presents itself showing "MP4 · transcribing", then transcript + word count; clipboard updated. First run: Speech Recognition permission prompt appears — approve it | BLOCKED | Forcing row. Popup re-presentation is not shipped because `PLAN-popup-persistence.md` is blocked; no GUI access to choose a file or approve prompts. |
| 13 | MP4 | Choose MP4 → Cancel in the picker | Popup returns; status unchanged; no error | BLOCKED | Popup-return behavior is blocked/unshipped; file picker UI could not be driven. |
| 14 | Transcript | Copy button | Clipboard equals the transcript pane text | BLOCKED | Requires popup interaction; assistive access denied. |
| 15 | Transcript | Save button → save to a temp folder | .txt file written whose contents equal the pane; popup returns | BLOCKED | Save flow requires GUI interaction, and popup-return behavior is blocked/unshipped. |
| 16 | Transcript | Save button → Cancel | No file written; popup returns | BLOCKED | Save panel cancel requires GUI interaction, and popup-return behavior is blocked/unshipped. |
| 17 | Notes | Type in Notes, close popup, reopen | Notes text still there (within the same run) | BLOCKED | Requires popup text entry and visual confirmation; assistive access denied. |
| 18 | Settings | Change YouTube accent color | Extract/Settings buttons recolor immediately; still applied after quit + relaunch | BLOCKED | Requires popup/settings interaction and visual confirmation; assistive access denied. |
| 19 | Settings | Launch at Login ON | Descript listed in System Settings > General > Login Items & Extensions; toggle OFF removes it | N/A | `PLAN-launch-at-login.md` was dependency-blocked by `PLAN-popup-persistence.md`; this feature is not shipped and is omitted from README. |
| 20 | Lifecycle | Right-click → Quit Descript | Icon disappears; process gone (`pgrep -x Descript` empty) | BLOCKED | Forcing row. Right-click Quit cannot be performed without assistive access; the QA instance was stopped with `kill 6006` after testing was blocked. |
| 21 | Resilience | Turn Wi-Fi off, Extract a YouTube URL | Clear error alert, app stays responsive; Wi-Fi back on, same URL succeeds | BLOCKED | Requires network/UI manipulation and packaged UI interaction; not performable from this environment. |

## Verdict

**DO-NOT-SHIP**

Justification: The signed 0.2.0 bundle builds, packages, verifies, and the YouTube service smoke passes, but the release cannot be shipped because required GUI QA is blocked by denied assistive access/screen capture, `PLAN-popup-persistence.md` is honestly logged as blocked, and `PLAN-launch-at-login.md` is dependency-blocked. Forcing rows 12 and 20 are BLOCKED, so the release verdict must be DO-NOT-SHIP. No `v0.2.0` tag should be created.
