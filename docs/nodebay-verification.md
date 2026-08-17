# Nodebay 0.1.0 verification record

This record separates completed checks from checks that still require an unlocked Mac, hardware, credentials, or publication infrastructure. It describes the current `feature/nodebay` branch based on Boring Notch `dev` commit `44dd999f70493da48209c99e9f873c47f2e55c83`.

## Environment

- Apple Silicon (`arm64`)
- macOS 26.6.1
- Xcode 26.6
- Minimum supported macOS: 15.0 (Sequoia)
- Bundled MarkItDown: 0.1.7
- Bundled Python: 3.13.15
- PyInstaller: 6.22.1
- Tested companion yt-dlp: 2026.7.4
- Tested companion FFmpeg: Homebrew 9.0.1
- Tested companion ImageOptim: locally installed application

## Passed

- Pinned MarkItDown runtime rebuild on Apple Silicon.
- Real PDF-to-Markdown fixture.
- Real DOCX-to-Markdown fixture.
- Source files remain byte-for-byte unchanged during conversion.
- Local-only runtime guard rejects URL inputs.
- Collision-safe output and existing Markdown eligibility contracts.
- Downloader URL, structured-argument, path, cookie, and configuration safety contracts.
- XPC engine allowlist and isolation contracts.
- Privacy manifest and release privacy contracts.
- Generated dependency notices match the pinned manifest.
- ImageOptim copy-first fixture: source hash remained unchanged and the generated copy was valid and smaller.
- Clean Debug build.
- Clean Release build for Apple Silicon.
- Application and bundled MarkItDown architectures are `arm64`.
- The release archive includes GPL-3.0, foundation attribution, runtime notices, privacy information, and corresponding-source instructions.
- Developer ID deep signature and hardened-runtime verification.
- Release artifact excludes the debug `get-task-allow` entitlement from the application and XPC helper.
- Pre-notarization artifact SHA-256: `3e073e3311159047246cc8de39810dd6b6506cfd8c1172287291dddde74183c1`.

## Pending final artifact checks

- Gatekeeper assessment after notarization. The current Developer ID candidate is rejected as `Unnotarized Developer ID`, as expected before submission.
- Notarization and stapling. This requires an authorized Apple submission and is intentionally not performed before final publication approval.
- Homebrew cask checksum update for the final signed and notarized archive.
- `brew style` and `brew audit` inside the proposed public tap.

## UI and hardware checks currently unavailable

- Light and dark appearance screenshots from the final signed build.
- End-to-end app-routed conversion, download, compression, removal/Undo, stack, and multi-file Finder drag flows.
- VoiceOver, keyboard focus, hit-target, reduced-motion, and context-menu regression passes.
- Built-in and external-display tests, hot-plugging, clamshell mode, mixed scaling, rotation, Spaces, full-screen apps, Mission Control, Stage Manager, and changing the main display.
- Large-batch memory and termination recovery testing.
- Individual browser-tab media control. The browser bridge is deliberately reported as unavailable and has not been claimed as implemented.

## Known limitations

- Nodebay retains the legacy `theboringteam.boringnotch` bundle identifier for a migration-safe first release. User-facing branding is Nodebay.
- yt-dlp, FFmpeg, and ImageOptim are separately installed companions. They are not bundled in the release archive.
- Multiple system media providers have independent registry state, but public macOS APIs do not guarantee enumeration or control of every third-party session.
- The project builds with warnings inherited from the foundation and some future Swift 6 concurrency warnings. These warnings do not currently fail the Swift 5 build, but they remain maintenance work.
- The proposed Homebrew command cannot work until an approved GitHub release and tap are published.
