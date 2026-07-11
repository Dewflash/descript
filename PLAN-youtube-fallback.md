# PLAN-youtube-fallback — don't let the Android player path kill the caption fallback

- **Rank:** 2 of 5
- **Dependencies:** run AFTER PLAN-verify-script (needs `./verify.sh` for the gate).
  Independent of all other plans.
- **Effort:** Small (~20 min)
- **Files touched:** `Sources/TranscriptServices.swift`. Nothing else.

## Goal

Confirmed bug in the primary user flow (YouTube URL → transcript).

`YouTubeTranscriptService.fetchTranscript(from:)` (Sources/TranscriptServices.swift:50–65)
tries two strategies in order:

1. `fetchTranscriptViaAndroidPlayer(videoID:apiKey:)` — Innertube ANDROID client
2. fallback: caption tracks scraped from the watch-page HTML via `captionTracks(fromHTML:)`

The android call is written as `try await` inside an `if let … , let text = try await …`
condition. If that function **throws** — which it does for any non-OK
`playabilityStatus` (e.g. age-gated videos return `LOGIN_REQUIRED` to the ANDROID client,
see lines 104–108), any non-2xx HTTP response (`assertSuccessfulHTTP`, line 98), or a JSON
parse failure (lines 100–102) — the error propagates straight out of `fetchTranscript` and
**the HTML fallback on line 59 never runs**, even when the watch page contains perfectly
usable caption tracks. The user sees "failed" for a video the app could have transcribed.

Bonus fix: `DescriptError.missingCaptionTracks` (defined at line 8) is currently dead code —
the "no tracks found in HTML" case wrongly throws `noTranscriptText`. This plan makes the
error honest.

## Steps

1. In `Sources/TranscriptServices.swift`, replace the entire body of
   `static func fetchTranscript(from input: String) async throws -> String`
   (currently lines 50–65) with exactly:

```swift
    static func fetchTranscript(from input: String) async throws -> String {
        let videoID = try extractVideoID(from: input)
        let html = try await fetchWatchHTML(videoID: videoID)

        var androidPlayerError: Error?
        if let apiKey = firstRegexCapture(#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#, in: html) {
            do {
                if let text = try await fetchTranscriptViaAndroidPlayer(videoID: videoID, apiKey: apiKey) {
                    return text
                }
            } catch {
                androidPlayerError = error
            }
        }

        guard let tracks = captionTracks(fromHTML: html) else {
            throw androidPlayerError ?? DescriptError.missingCaptionTracks
        }

        guard let text = try await fetchTranscript(fromTracks: tracks) else {
            throw androidPlayerError ?? DescriptError.noTranscriptText
        }

        return text
    }
```

2. Run `./verify.sh` — the smoke exercises the real happy path against youtube.com.

## Edge cases a weaker model would miss

- **Copy the regex literal exactly, including the `#` delimiters:**
  `#""INNERTUBE_API_KEY":\s*"([a-zA-Z0-9_-]+)""#`. It is a Swift raw string; dropping the
  `#`s changes escaping and the pattern silently stops matching, which disables the android
  path entirely (the app would still work via fallback, so no test catches it — the
  regression would be invisible).
- **`androidPlayerError` is preferred over the generic errors when BOTH paths fail.** The
  android error carries YouTube's actual reason ("Sign in to confirm your age", "Video
  unavailable"). If the fallback also finds nothing, that reason is the user-actionable
  truth; throwing `missingCaptionTracks` instead would mislead. Do not "simplify" the
  `androidPlayerError ?? …` expressions away.
- **Do NOT wrap the fallback path (`fetchTranscript(fromTracks:)`) in a `do/catch` too.**
  It is the last resort; its errors must propagate unchanged so the user sees what happened.
- **Do not modify `fetchTranscriptViaAndroidPlayer` itself.** Its throw-on-bad-status
  behavior is correct — that is how the playability reason is captured. The fix belongs at
  the call site only.
- **Do not add retries, backoff, or logging.** The app's error surface is a single alert;
  keep behavior deterministic.
- **`missingCaptionTracks` was dead code, now live — don't delete it** and don't rename it;
  its `errorDescription` ("No transcript track was found for this YouTube video.") is
  already user-facing copy.

## Acceptance criteria

1. `./verify.sh; echo "exit=$?"` → `VERIFY OK`, `exit=0` (smoke still returns
   `OK words=` ≥ 50 — the happy path is unchanged).
2. `grep -c "androidPlayerError" Sources/TranscriptServices.swift` → `4` (declaration,
   catch assignment, two fallback throws).
3. `grep -c "missingCaptionTracks" Sources/TranscriptServices.swift` → `3` (enum case,
   errorDescription case, one throw site).
4. Manual (optional, network-dependent): in the built app, extracting an age-restricted
   video that has captions now yields a transcript instead of an immediate failure. If no
   such video is at hand, skip — criteria 1–3 cover the code change.
5. `git status --porcelain` after commit → empty.

Suggested commit message:

    fix: fall back to watch-page captions when Android player path fails
