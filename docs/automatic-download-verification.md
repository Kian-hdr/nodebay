# Automatic downloader revision: verification

Checked 2026-09-02 on Apple Silicon, macOS 26.6.2, Xcode 26.6.

Source: local `fix/automatic-media-detection` worktree based on `c732fa02c63eb065d59468b837835ae21eca352b`. Changes are uncommitted and unpublished. Existing unrelated proposal drafts were preserved. No engine dependency or license changed.

## Implementation

- Automatic remains the default. Single-item downloads start after inspection without a format prompt; playlists still require confirmation.
- Classification uses the Music source URL, audio-only evidence checked against available video formats, or structured track and artist metadata. Missing/ambiguous metadata, titles and categories alone fall back to video.
- Tiles display the effective output and provide a direct Audio/Video override. Native buttons and menus retain the existing tile footprint. Missing-FFmpeg audio controls are disabled and setup help is available; video falls back to combined streams without merging.
- Each automatic playlist item is inspected and classified separately. Fixed reasons, confidence and item ordinals are persisted without copying private metadata into classification diagnostics.
- Cancellation and overrides retain completed playlist outputs, ignore stale progress and wait for the previous job to stop. Outputs remain collision-safe, ordinary files; completed playlists are stacks even when only one item succeeds.
- Native UI changes follow the macOS design skill's stable-layout, semantic-control and accessible-label guidance. No Apple artwork, new runtime, or external service was added.

## Automated verification

| Check | Result | Evidence |
|---|---|---|
| Complete automated suite | Passed | 124 Python test cases, including compiled Swift classifier/coordinator harnesses |
| Classification fixtures | Passed | YouTube Music, standard YouTube, youtu.be, Shorts, official track/artist metadata, audio-only, selected audio with video formats, ambiguous/missing metadata, hostname spoof, empty metadata, fixed private-data-free reasons and confidence |
| Actual coordinator with mocked platform/engine boundaries | Passed | All four modes, saved settings, automatic no-picker path, Ask picker, MP3/MP4 quality selection, shelf publication, per-item playlist inspection, partial failure, single-result stack, confirmation rejection, empty playlist, fixed playlist override, cancellation retaining results, restart overrides, missing FFmpeg, persisted decisions |
| Production output-promotion logic with simulated engine files | Passed | Duplicate names produce different destinations; original bytes preserved |
| Real local yt-dlp and FFmpeg fixture | Passed | Generated 1-second video/tone served only on localhost; MP4 downloaded and MP3 extracted at 192 kbps; ffprobe stream checks and full FFmpeg decoding succeeded |
| MarkItDown runtime regression | Passed | PDF, DOCX, original hashes, local-only guard and runtime notices |
| Clean arm64 Debug build | Passed | `xcodebuild ... -configuration Debug -destination 'platform=macOS,arch=arm64' ... CODE_SIGNING_ALLOWED=NO clean build` |
| Clean arm64 Release build | Passed | Same command with Release; executable architecture confirmed arm64 |
| Repository/notices/shell/diff checks | Passed | `verify_repository.py`, `generate_nodebay_notices.py --check`, `zsh -n scripts/test_downloader_local.sh`, `git diff --check` |

The complete suite combines source-contract checks with executable behavioral fixtures. Coordinator tests use isolated UserDefaults and a shelf double, not the installed app or the user's files. The real-media fixture validates the external engines, not the full notch UI or YouTube service availability.

Local, disposable evidence paths:

- `/tmp/nodebay-auto-check.X554w4/tests-final.log`
- `/tmp/nodebay-auto-check.X554w4/media-fixture.log`
- `/tmp/nodebay-auto-build.8uGUas/debug-final.log`
- `/tmp/nodebay-auto-build.8uGUas/release-final.log`

## Physical UI and release verification

| Check | Result | Limitation |
|---|---|---|
| New tile controls in light/dark mode, keyboard and VoiceOver | Not run | Candidate was not launched against the live user's shelf/preferences |
| Actual YouTube audio/video download through the notch | Not run | Deterministic local media and mocked metadata used; live provider behavior is not claimed |
| Physical built-in/external display drag and playback | Not run | Requires an interactive candidate session |
| Instruments/memory/performance audit | Not run | Builds and mocks do not establish UI responsiveness |
| Developer ID signing, notarization and packaging | Not run | These are unsigned verification builds, not distribution artifacts |
| Publication/Homebrew release update | Not run | Final verification and explicit publication approval still required |

The installed and published Nodebay 1.0.0 remain untouched. Temporary build registrations are removed from Launch Services after verification. Pre-existing compiler warnings (including media-controller locking and deprecated APIs) remain; successful compilation does not mean warning-free code.

Next release gate: exercise the revised tile, overrides, missing-engine recovery and playlist flow in an isolated interactive candidate; then prepare a newly versioned signed/notarized artifact and exact approval proposal. Do not overwrite the existing 1.0.0 release.
