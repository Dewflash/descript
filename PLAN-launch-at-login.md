# PLAN-launch-at-login — the toggle that makes it a real menu-bar utility

- **Rank:** 4 of 5
- **Dependencies:** run AFTER PLAN-verify-script AND after PLAN-popup-persistence (both
  plans edit `Sources/DescriptModel.swift` and `Sources/DescriptApp.swift`; the line
  anchors below assume popup-persistence has landed).
- **Effort:** Medium (~45 min)
- **Files touched:** `Sources/DescriptModel.swift`, `Sources/DescriptApp.swift`, `build.sh`.
  Nothing else.

## Goal

The one capability that completes the product story. Descript's promise is "always one
click away in the menu bar" — but today the user must manually relaunch it after every
reboot, which is exactly when a background utility silently stops existing. A
"Launch at login" toggle in the existing Settings panel closes that gap using Apple's
`SMAppService` (macOS 13+, matching `LSMinimumSystemVersion` 13.0 in Info.plist — no
availability checks needed). No new third-party dependencies; `ServiceManagement` is a
system framework.

## Step 0 — feasibility probe (platform behavior, cheap)

This plan hinges on `SMAppService` being present in the local SDK. Verified working on this
machine on 2026-07-11 (printed `3` = `.notFound`, exit 0 — expected for a bare binary), but
re-verify cheaply before touching anything:

```bash
cat > /tmp/descript-sm-probe.swift <<'EOF'
import ServiceManagement
print("SMAppService probe status:", SMAppService.mainApp.status.rawValue)
EOF
swiftc -o /tmp/descript-sm-probe /tmp/descript-sm-probe.swift && /tmp/descript-sm-probe
```

Expected: compiles, runs, prints `SMAppService probe status:` followed by an integer,
exit 0. **If this fails: STOP and report — do not improvise.** Log to BLOCKERS.md and move
on to PLAN-final-polish (which does not depend on this plan, but see its BLOCKERS note).

## Steps

1. In `Sources/DescriptModel.swift`, add `import ServiceManagement` between the existing
   `import Foundation` and `import SwiftUI` lines (imports stay alphabetical).

2. Same file: directly under `@Published var mp4Accent: Accent` (the last `@Published`
   property), add:

```swift
    @Published var launchAtLogin = false
```

3. Same file, in `init()`, after the two accent assignments, add:

```swift
        launchAtLogin = SMAppService.mainApp.status == .enabled
```

4. Same file: directly after the closing brace of `setAccent(_:for:)`, add:

```swift
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showError("Could not update the login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
```

5. In `Sources/DescriptApp.swift`, inside `settingsPanel` (the
   `private var settingsPanel: some View` builder), directly after the line
   `colorChooser(title: "MP4", source: .mp4)`, add:

```swift
            launchAtLoginRow
```

6. Same file: directly after the closing brace of the `colorChooser(title:source:)`
   function, add:

```swift
    private var launchAtLoginRow: some View {
        HStack {
            Text("LAUNCH AT LOGIN")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.zinc500)
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(model.activeAccent.color)
        }
        .padding(12)
        .background(Color.zinc900.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.zinc800))
    }
```

7. In `build.sh`, inside the `swiftc` invocation (lines 18–29), add a new line after
   `  -framework Speech \`:

```bash
  -framework ServiceManagement \
```

   Keep the trailing backslash — every framework line except the last has one.

8. Run `./verify.sh`, then the manual checks.

## Edge cases a weaker model would miss

- **Use the custom `Binding` from step 6 — NOT `$model.launchAtLogin`.** A direct binding
  writes the `@Published` bool without ever calling `register()`/`unregister()`: the toggle
  animates, nothing happens, and no check catches it. The custom binding routes the gesture
  through `setLaunchAtLogin`.
- **The toggle may legitimately snap back to OFF after enabling.** `register()` can land in
  `.requiresApproval` (user must approve in System Settings > General > Login Items); the
  final `status == .enabled` read then reports `false`, and the toggle reflecting the real
  state is CORRECT. Do not force `launchAtLogin = true` on the success path.
- **`SMAppService` registers the bundle at its current on-disk path.** Enabling from
  `build/Descript.app` and then rebuilding/moving the app leaves a stale login item. Do not
  chase this in code — the release QA (PLAN-final-polish) tests the toggle from
  `/Applications`, which is the path real users run.
- **Swift auto-links imported Apple frameworks, so the build would succeed even without
  step 7.** Add the flag anyway: the script's style is fully explicit framework linking,
  and an implicit dependency is the kind that breaks silently under a future
  `-disable-autolink` or toolchain change.
- **No `#available`/`@available` guards.** Minimum deployment is already macOS 13.0 and
  `SMAppService.mainApp` is 13.0+. Adding guards is dead code that suggests the API might
  be missing.
- **The probe binary in Step 0 registers nothing** — `.notFound` (rawValue 3) is the
  expected status for a bare CLI binary. It proves the API compiles and links, nothing
  more. Do not try to `register()` from the probe.
- **Keep `showError` (not a silent failure) in the catch branch** — it inherits the
  popup re-present behavior from PLAN-popup-persistence, so the user actually sees why the
  toggle failed.

## Acceptance criteria

Mechanical:

1. `./verify.sh; echo "exit=$?"` → `VERIFY OK`, `exit=0`.
2. `grep -c "ServiceManagement" build.sh` → `1`.
3. `grep -c "setLaunchAtLogin" Sources/DescriptApp.swift` → `1` (the binding's set closure).

Manual (launch the freshly built `./build/Descript.app`; quit any older running copy first):

4. Open popup → Settings → a "LAUNCH AT LOGIN" row with a switch appears under the two
   color choosers, styled like the rest of the panel.
5. Toggle ON → open System Settings > General > Login Items & Extensions. PASS = an entry
   for Descript appears under "Open at Login" (or the toggle visibly snaps back OFF, which
   means approval is pending — also a PASS for wiring; note which happened).
6. Toggle OFF → the entry disappears from System Settings.

Suggested commit message:

    feat: add launch-at-login toggle to settings
