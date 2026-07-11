# PLAN-verify-script — one-command mechanical verification

- **Rank:** 1 of 5 (run FIRST — every other plan's gate depends on it)
- **Dependencies:** none (independent)
- **Effort:** Small (~30 min)
- **Files touched:** `verify.sh` (new), `SmokeYouTube.swift`. Nothing else.

## Goal

The repo has zero runnable verification: no tests, no lint config, and `SmokeYouTube.swift`
exists but no command compiles or runs it. Every later plan needs a gate, so this plan creates
`./verify.sh` = typecheck + full bundle build + live YouTube smoke. This directly protects the
product promise (transcript extraction working end-to-end) against every future change.

Baseline recorded at HEAD `a59667c` on 2026-07-11 (Apple Swift 6.3.2, target
`arm64-apple-macosx26.0`, SDK MacOSX26.5) — all three checks below were run and were green:

- `swiftc -typecheck -parse-as-library Sources/DescriptApp.swift Sources/DescriptModel.swift Sources/TranscriptServices.swift` → exit 0
- `./build.sh` → exit 0, produces `build/Descript.app`, `release/Descript-0.1.0.zip`, `release/Descript-0.1.0.dmg`
- smoke compile + run → printed `OK words=5199`, exit 0

Four compiler warnings are ACCEPTED BASELINE (do not fix, do not promote to errors):

1. `Sources/TranscriptServices.swift:463` — `exportAsynchronously(completionHandler:)` deprecated in macOS 15.0
2. `Sources/TranscriptServices.swift:464` — `status` deprecated in macOS 15.0
3. `Sources/TranscriptServices.swift:468` — `error` deprecated in macOS 15.0
4. `Sources/TranscriptServices.swift:464` — capture of `export` (non-Sendable `AVAssetExportSession`) in a `@Sendable` closure

## Steps

1. Replace the entire contents of `SmokeYouTube.swift` with exactly:

```swift
import Foundation

@main
struct SmokeYouTube {
    static func main() async {
        let url = ProcessInfo.processInfo.environment["DESCRIPT_SMOKE_URL"]
            ?? "https://www.youtube.com/watch?v=dg9Ezg_RS6E"
        do {
            let transcript = try await YouTubeTranscriptService.fetchTranscript(from: url)
            let words = transcript.split { $0.isWhitespace || $0.isNewline }.count
            guard words >= 50 else {
                print("ERROR transcript too short: words=\(words)")
                exit(1)
            }
            print("OK words=\(words)")
            print(String(transcript.prefix(500)))
        } catch {
            print("ERROR \(type(of: error)): \(error.localizedDescription)")
            exit(1)
        }
    }
}
```

   **Assertion change, spelled out:** the old smoke printed `OK` for ANY returned string,
   including a 1-word junk parse. The new smoke fails (`exit 1`) when the transcript has
   fewer than 50 words, and the smoke video can be overridden with `DESCRIPT_SMOKE_URL`.
   The known-good video `dg9Ezg_RS6E` returned 5199 words on 2026-07-11, so 50 is a
   deliberately loose floor that catches junk/truncated parses without failing legitimate
   short override videos.

2. Create `verify.sh` at repo root with exactly:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export COPYFILE_DISABLE=1

echo "==> [1/3] Typecheck app sources"
swiftc -typecheck -parse-as-library \
  Sources/DescriptApp.swift \
  Sources/DescriptModel.swift \
  Sources/TranscriptServices.swift

echo "==> [2/3] Build app bundle and release artifacts"
./build.sh

echo "==> [3/3] YouTube transcript smoke (network)"
if [[ "${DESCRIPT_SKIP_NETWORK:-0}" == "1" ]]; then
  echo "SKIPPED network smoke (DESCRIPT_SKIP_NETWORK=1) — gates require the full run"
else
  swiftc -O -parse-as-library \
    -o build/smoke-youtube \
    SmokeYouTube.swift \
    Sources/TranscriptServices.swift \
    -framework AVFoundation \
    -framework Speech \
    -framework UniformTypeIdentifiers
  ./build/smoke-youtube
fi

echo "VERIFY OK"
```

3. Make it executable: `chmod +x verify.sh`

4. Run `./verify.sh` and confirm it exits 0 with `VERIFY OK` as the last line.
   Note: it opens **no GUI windows** — safe to run headless. It DOES hit youtube.com
   in step 3 (takes ~5–15 s) and rebuilds the zip/dmg in step 2 (~10 s).

## Edge cases a weaker model would miss

- **Compile order inside verify.sh is load-bearing.** `build.sh` starts with
  `rm -rf build/` (build.sh line 15). If you compile the smoke binary before running
  `./build.sh`, the binary is deleted before it runs. Smoke compile MUST come after the
  bundle build.
- **Never compile `SmokeYouTube.swift` together with `Sources/DescriptApp.swift` or
  `Sources/DescriptModel.swift`.** Both `DescriptApp` and `SmokeYouTube` declare `@main`;
  combining them is a hard compile error ("'main' attribute can only apply to one type").
  The smoke binary links exactly two files: `SmokeYouTube.swift` +
  `Sources/TranscriptServices.swift`.
- **`-parse-as-library` is required in both swiftc invocations.** Without it, `@main` in a
  file compiled by bare `swiftc` fails ("'main' attribute cannot be used in a module that
  contains top-level code").
- **Do not add `-warnings-as-errors` or "fix" the 4 baseline warnings.** They come from
  AVFoundation deprecations in the macOS 15+ SDK; fixing them means rewriting
  `AudioExtractor.exportAudio` against a newer async API — out of scope, and making
  warnings fatal turns every future SDK bump into a red gate.
- **`DESCRIPT_SKIP_NETWORK=1` is an offline-development escape hatch only.** A plan gate is
  never satisfied by a skipped smoke — AGENTS.md states this; do not "helpfully" skip when
  the network is flaky. A failing smoke is a BLOCKERS.md entry, not a skip.
- **`Sources/TranscriptServices.swift` must stay free of AppKit/SwiftUI imports.** The smoke
  binary is a CLI tool; if a future change adds UI imports there, the smoke build breaks.
  (This invariant is also in AGENTS.md.)
- **Word threshold stays at 50.** Raising it (e.g., to 1000) breaks legitimate short
  override videos; lowering it to 0 re-opens the junk-parse hole this plan closes.

## Acceptance criteria

1. `./verify.sh; echo "exit=$?"` → prints `VERIFY OK` then `exit=0`.
2. `./verify.sh` output contains `OK words=` with a number ≥ 50 (network smoke actually ran).
3. `DESCRIPT_SKIP_NETWORK=1 ./verify.sh; echo "exit=$?"` → prints the SKIPPED line and `exit=0`.
4. `test -x verify.sh && echo executable` → prints `executable`.
5. `git status --porcelain` after commit → empty.

Suggested commit message:

    build: add one-command verify script and harden YouTube smoke
