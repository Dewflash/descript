# AGENTS.md — Descript execution roadmap

You are executing a pre-planned polish-and-release roadmap for **Descript**, a native macOS
menu-bar app (SwiftUI + AppKit, plain `swiftc` build via `build.sh` — no Xcode project, no
SwiftPM, no package manager). This file and the five `PLAN-*.md` files at repo root are the
complete spec; you need no other context.

Core product promise — judge every decision against it:

> One click in the menu bar turns a YouTube link or a local MP4 into a clean plain-text
> transcript on your clipboard within seconds — no browser, no cloud, no setup.

## Step 0 — before anything else

Commit the handover docs exactly as found:

```bash
git add AGENTS.md PLAN-verify-script.md PLAN-youtube-fallback.md PLAN-popup-persistence.md PLAN-launch-at-login.md PLAN-final-polish.md
git commit -m "docs: add execution roadmap"
```

Do not edit the plans while committing them. This protects the roadmap from stray checkouts.

## Execution order and dependency graph

Run ONE plan per session. A plan must be fully done (gate green + committed) before the
next one starts.

| Order | Plan | Depends on | Effort |
|---|---|---|---|
| 1 | PLAN-verify-script.md | nothing | S |
| 2 | PLAN-youtube-fallback.md | 1 | S |
| 3 | PLAN-popup-persistence.md | 1 (independent of 2) | M |
| 4 | PLAN-launch-at-login.md | 1 and 3 (same files as 3) | M |
| 5 | PLAN-final-polish.md | all of the above — always last | L |

## The hard gate — after every plan

A plan is DONE only when ALL three hold:

1. `./verify.sh` exits 0 and prints `VERIFY OK` — the FULL run. A run with
   `DESCRIPT_SKIP_NETWORK=1` never satisfies a gate. (For plan 1, creating `verify.sh` IS
   the work; the gate applies from the moment it exists.)
2. Every acceptance criterion listed in that plan's own file passes, including the manual
   checks with their observable pass conditions.
3. The work is committed using the plan's suggested commit message.

**Never weaken a gate on your own.** Do not lower the smoke word threshold, skip the network
smoke, loosen a grep count, delete an acceptance criterion, add `|| true`, or mark a manual
check passed without performing it. If a gate cannot pass, use the failure protocol.

`./verify.sh` opens no GUI windows (safe headless) but needs network for the YouTube smoke
and ~30 s to rebuild the bundle + zip + dmg.

## Failure protocol

- Revert to the last green commit: `git reset --hard <last-green-sha>`. Never half-land a
  plan; never commit a broken intermediate state.
- Append to `BLOCKERS.md`: the plan name, the exact failing command, its FULL output, and
  what you tried.
- Continue only with plans that do not depend on the blocked one (see the table). A blocked
  plan 3 blocks plan 4; plan 5 still runs but must honor its BLOCKERS rules (README and QA
  rows for missing features).
- If PLAN-verify-script itself is blocked, stop the whole engagement — everything gates on
  it.

## House rules

- **No new runtime dependencies.** Apple system frameworks only; the sole planned addition
  is `ServiceManagement` (PLAN-launch-at-login). No SwiftLint, no xcodebuild, no
  Package.swift, no Homebrew, no Python.
- **Match existing style:** 4-space-indented Swift, `set -euo pipefail` bash, tab-indented
  Info.plist, minimal comments. No file renames.
- **Never commit:** `build/`, `release/`, `.DS_Store`, media files (.mp4/.m4a), or secrets.
  They are gitignored — never force-add them.
- **Never touch anything outside this repo directory.** `../../outputs/` and `../../python/`
  are stale exports of earlier prototypes; they are not part of this project.
- **Architecture invariants:**
  - `Sources/TranscriptServices.swift` never imports AppKit or SwiftUI — the CLI smoke
    binary links it standalone and would break.
  - Exactly two `@main` types exist (`DescriptApp`, `SmokeYouTube`) and they are never
    compiled into the same binary.
  - `DescriptModel` is the single source of UI state, owned by `AppDelegate`; everything
    UI-touching stays on the main actor.
  - The 4 compiler warnings listed in PLAN-verify-script.md are accepted baseline — do not
    fix them and do not promote warnings to errors.
- **Git:** identity is already configured (Kevin Yong <kevinyongcj@gmail.com>). Commit
  locally only — NEVER `git push` unless Kevin explicitly asks. Tag only as PLAN-final-polish
  instructs.

## Definition of done (whole engagement)

- All five plans landed green and committed — or blocked ones honestly logged in
  `BLOCKERS.md` with the protocol above.
- `./verify.sh` green at final HEAD.
- `RELEASE-QA.md` committed with every row filled and an explicit SHIP or DO-NOT-SHIP
  verdict.
- Tag `v0.2.0` exists if and only if the verdict is SHIP.
- Working tree clean. Nothing pushed.
