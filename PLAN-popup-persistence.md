# PLAN-popup-persistence — bring the popup back after modal dialogs close it

- **Rank:** 3 of 5
- **Dependencies:** run AFTER PLAN-verify-script. Independent of PLAN-youtube-fallback
  (different file). Must run BEFORE PLAN-launch-at-login (that plan edits the same files).
- **Effort:** Medium (~45 min)
- **Files touched:** `Sources/DescriptModel.swift`, `Sources/DescriptApp.swift`. Nothing else.

## Goal

Biggest friction in the primary flow. The popover is created with
`popover.behavior = .transient` (Sources/DescriptApp.swift:36), which means macOS closes it
the moment any other window takes key status. Three places in `DescriptModel` open modal
windows via `runModal()`:

- `chooseMP4()` — `NSOpenPanel` (Sources/DescriptModel.swift:141)
- `saveTranscript()` — `NSSavePanel` (Sources/DescriptModel.swift:174)
- `showError(_:)` — `NSAlert` (Sources/DescriptModel.swift:193)

Consequence for the MP4 flow (worst case): the user clicks "Choose MP4", the popup vanishes,
they pick a file, and then **nothing visible happens** — transcription runs behind a closed
popup. The user must re-click the menu bar icon to discover whether anything worked. Save
and error alerts have the same dead-end shape.

Fix: after any modal returns, the model asks the app delegate to re-present the popup. State
already survives (the model is owned by `AppDelegate`), so this is pure wiring.

## Steps

All code below is `@MainActor` already — `DescriptModel` and `AppDelegate` are both
`@MainActor` classes. Do not add `DispatchQueue` or `Task` wrappers.

1. In `Sources/DescriptModel.swift`, directly under the line
   `private let defaults = UserDefaults.standard` (line 72), add:

```swift
    var presentPopup: (() -> Void)?
```

   Plain `var` — deliberately NOT `@Published` (see edge cases).

2. In `chooseMP4()` (Sources/DescriptModel.swift:131), replace the single line

```swift
        guard panel.runModal() == .OK, let url = panel.url else { return }
```

   with:

```swift
        let response = panel.runModal()
        presentPopup?()
        guard response == .OK, let url = panel.url else { return }
```

3. Replace the entire body of `saveTranscript()` (Sources/DescriptModel.swift:169–181) with:

```swift
    func saveTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript.txt"

        let response = panel.runModal()
        defer { presentPopup?() }
        guard response == .OK, let url = panel.url else { return }

        do {
            try transcript.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError(error.localizedDescription)
        }
    }
```

4. Replace the entire body of `showError(_:)` (Sources/DescriptModel.swift:188–194) with:

```swift
    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Descript"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
        presentPopup?()
    }
```

5. In `Sources/DescriptApp.swift`, inside `applicationDidFinishLaunching`, directly after
   the line `self.popover = popover` (line 43), add:

```swift
        model.presentPopup = { [weak self] in
            self?.presentPopupIfNeeded()
        }
```

6. Still in `Sources/DescriptApp.swift`, add this method to `AppDelegate`, directly after
   the closing brace of `togglePopup(from:)` (line 65):

```swift
    private func presentPopupIfNeeded() {
        guard let popover, let button = statusItem?.button else { return }
        guard !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
```

7. Run `./verify.sh`, then do the three manual checks below.

## Edge cases a weaker model would miss

- **Do NOT "fix" this by changing `popover.behavior` away from `.transient`.** Transient is
  what makes the popup close when the user clicks elsewhere — core menu-bar-app UX. The fix
  is re-presenting after system-forced closes, not preventing closes.
- **`presentPopup?()` must run AFTER `runModal()` returns — never before.** A popup shown
  while a modal is up either hides behind it or instantly transient-closes when the modal
  takes key again. This ordering is the whole plan. (In `saveTranscript` the `defer` is
  declared after `runModal()` returns, so it is safe; `defer` also guarantees the popup
  returns on the early-`return` cancel path.)
- **`[weak self]` in step 5 is required.** `AppDelegate` strongly owns `model`
  (line 17); a strong capture of `self` in a closure stored on `model` is a retain cycle.
  The app "works" anyway (the delegate lives forever), which is exactly why a careless
  executor wouldn't notice — keep it correct.
- **`presentPopupIfNeeded` must guard `popover.isShown`.** In `saveTranscript`, a write
  failure calls `showError` (which presents) and then the `defer` presents again. The guard
  makes the second call a no-op instead of a flicker/re-anchor.
- **`presentPopup` stays non-`@Published`.** It is wiring, not view state. Publishing it
  fires `objectWillChange` on assignment during `applicationDidFinishLaunching` and on every
  future reassignment — pointless view invalidation at best.
- **Intended behavior change, do not "restore" it:** the cancel path of the MP4 picker and
  save panel now re-opens the popup (previously it stayed closed). Rationale: the user was
  mid-flow in the popup when the modal stole it; cancelling the dialog should return them
  to where they were. Likewise, a YouTube extraction error alert now re-opens the popup
  after dismissal even if the user closed the popup while waiting.
- **No existing mechanical check asserts popover behavior** (the smoke is network-only), so
  `verify.sh` needs no changes and its assertions stay identical. The manual checks below
  are the real acceptance for this plan.

## Acceptance criteria

Mechanical:

1. `./verify.sh; echo "exit=$?"` → `VERIFY OK`, `exit=0`.
2. `grep -c "presentPopup" Sources/DescriptModel.swift` → `4` (declaration + 3 call sites).
3. `grep -c "presentPopupIfNeeded" Sources/DescriptApp.swift` → `2` (wiring + definition).

Manual (launch `./build/Descript.app` fresh — quit any older running copy first via its
menu bar right-click → Quit):

4. MP4 flow: open popup → MP4 tab → "Choose MP4" → pick any .mp4 file. PASS = the popup
   re-appears by itself showing status "MP4 · transcribing" (then a result or an error —
   either is fine for THIS plan; visibility is what's under test).
5. Cancel flow: "Choose MP4" → press Cancel in the picker. PASS = popup re-appears, status
   unchanged.
6. Error flow: YouTube tab → type `not a url` → Extract → alert appears frontmost; dismiss
   it. PASS = popup re-appears on its own.

Suggested commit message:

    fix: re-present the popup after file pickers and error alerts
