# BLOCKERS

## PLAN-popup-persistence.md — blocked on macOS assistive access

Date: 2026-07-11
Last green commit: `fd59038`

Plan 3 code was implemented and the mechanical checks passed before reverting:

- `./verify.sh; echo "exit=$?"` completed with `OK words=5199`, `VERIFY OK`, and `exit=0`.
- `grep -c "presentPopup" Sources/DescriptModel.swift` returned `4`.
- `grep -c "presentPopupIfNeeded" Sources/DescriptApp.swift` returned `2`.

The mandatory manual checks could not be performed because this environment cannot inspect or drive the macOS UI.

Failing command:

```bash
osascript -e 'tell application "System Events" to tell process "Descript" to get {name, role, subrole, description} of every UI element'
```

Full output:

```text
67:101: execution error: System Events got an error: osascript is not allowed assistive access. (-1728)
```

Additional failing command:

```bash
screencapture -x /private/tmp/descript-access-check.png
```

Full output:

```text
could not create image from display
```

What I tried:

- Launched the freshly built `build/Descript.app`.
- Confirmed the Descript process started.
- Attempted to inspect the app with System Events accessibility scripting.
- Attempted to capture the display for coordinate/screenshot-based manual verification.
- Quit the launched Descript process.
- Reverted the uncommitted Plan 3 changes back to the last green commit, per the failure protocol.

Required unblock:

Grant the automation host assistive access, and preferably screen recording access, then rerun PLAN-popup-persistence.md from the last green commit. Without that access, the required manual checks cannot be honestly marked passed.

## PLAN-launch-at-login.md — blocked by popup persistence dependency

Date: 2026-07-11
Blocking plan: `PLAN-popup-persistence.md`
Last green implementation commit: `fd59038`

`PLAN-launch-at-login.md` depends on `PLAN-popup-persistence.md` according to `AGENTS.md`.
Because popup persistence could not be completed or committed, launch-at-login was not run.

Failing command:

```bash
osascript -e 'tell application "System Events" to tell process "Descript" to get {name, role, subrole, description} of every UI element'
```

Full output inherited from the blocking plan:

```text
67:101: execution error: System Events got an error: osascript is not allowed assistive access. (-1728)
```

What I tried:

- Confirmed `PLAN-launch-at-login.md` depends on `PLAN-popup-persistence.md`.
- Confirmed `PLAN-popup-persistence.md` is logged above as blocked on macOS assistive access.
- Skipped launch-at-login implementation rather than editing the same source files on top of an unlanded dependency.
- Removed launch-at-login from README and marked QA row 19 `N/A` in `RELEASE-QA.md`.

Required unblock:

Complete and commit `PLAN-popup-persistence.md`, then rerun `PLAN-launch-at-login.md` from a clean tree.
