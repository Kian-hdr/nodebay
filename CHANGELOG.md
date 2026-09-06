# Changelog

All notable Nodebay changes are recorded here. The project follows semantic versioning after its first public release.

## [1.2.0] - 2026-09-06

- Add opt-in **AI & Quick Chat** settings with Off, Codex CLI and OpenAI API
  modes. Off is the default. API mode uses the Responses API, macOS Keychain
  credentials and separate API billing. Both real connection validation and
  a synthetic native chat passed with `gpt-5-mini`; final artifact checks remain
  separate in the [verification matrix](docs/release-verification-matrix.md).
- Make the API key entry discoverable with a visible heading, explanatory
  text, a large bordered secure field and a direct paste placeholder.
- Keep user-message bubbles compact and right-aligned, fitting their text after
  window resizing. Measure text independently of its previous layout to prevent
  short messages from expanding into a wide empty bubble.
- Keep conversations in memory with configurable inactivity expiry and separate
  consent for Knowledge Folder cloud excerpts. Clearing local chat is not a
  promise of provider-wide deletion. Replies are delivered as complete messages.
- Replace the media-source menu with available-source tabs, add space above
  the title, retain paused sources with media, and clear unavailable metadata
  instead of showing sample titles. Correct QuickTime document selection.
- Add the optional Longhaul status and acknowledged automatic-protection toggle.
  Longhaul is a separate app requiring explicit pairing, with no public installer
  configured; it is not bundled or installed by Nodebay.
- Highlight the file drawer only while its native drop destination is targeted.
  Clear drag-approach state on release, Escape, and detector teardown so the
  drawer does not remain blue while idle.
- Keep new media downloads in the persistent notch file drawer until exported
  by drag. Ignore legacy custom-folder bookmarks, remove the download folder
  picker, and report storage failures instead of using temporary storage.
- Set application, helper and preview-extension version to 1.2.0 (25).
- Keep Codex CLI requests on the restricted worker with `--ignore-user-config`
  and explicit tool restrictions. App Server streaming remains disabled.
  See [Quick Chat](docs/features/quick-chat.md) for provider and privacy boundaries.
- Retain the installed startup fix without rebuilding the Codex database per
  request. Add one-message Think Deeper, defensive complete-message parsing,
  cancellation bounds, and preservation of the next draft and text selection.
- Anchor Home, Shelf and Chat to one shared header/content layout.
- Let Quick Chat close on hover-away without losing its temporary conversation
  or draft. Default to three hours of inactivity, preserve existing explicit
  timeout settings, and hold only active selection/composition/menu interactions.
- Fix Finder files failing to enter or persist in the shelf when overlapping
  SwiftUI drop destinations produced a reentrant AppKit drag transaction. Use
  one stable notch-level intake destination while preserving tile stacking and
  AirDrop, and verify real `NSItemProvider` bookmark capture and resolution.

## [1.1.0] - 2026-09-03

- Add a sandboxed native Markdown Quick Look extension with selectable text, tables, task lists and code, backed by a separate Foundation/AppKit renderer. Keep system-owned translucent chrome and background, with no network resources, extra document surface or branding. Includes bounded parsing, source-preservation tests and Finder verification with Nodebay quit.

- Add local STL Repair using the separate, unmodified Blender 5.0.1 companion: Safe, confirmed Thorough and Inspect modes, collision-safe persistent copies, batch partial successes, native reports and shared engine settings. Self-intersection repair and online uploads are not implemented; release gates are in `docs/stl-repair-verification.md`.

- Add privacy-first Quick Notes: explicit shelf paste creates persistent Markdown, with deterministic URL/file routing, a native New Note editor, configurable safe filenames, bounded local rich-text conversion and redacted diagnostics.
- Reuse regular file tiles, Quick Look, drag, stacks, reference-only removal and Undo for notes; keep the result visible with a brief dismissible confirmation.

- Show the inspected Audio/MP3 or Video/MP4 choice on download tiles, with a direct one-click override and disabled MP3 controls when FFmpeg is unavailable.
- Require structured track and artist metadata for music detection. A selected audio stream does not imply an audio-only upload when video formats exist; titles and music categories alone never decide the format.
- Preserve YouTube Music playlist URLs and privacy-safe per-item classification decisions. Keep partial successes and single-result playlists in File Stacks.
- Serialize format overrides with cancellation, ignore stale progress, and retain completed playlist files after cancellation.
- Add executable coordinator fixtures and local MP4/MP3 download-and-decode checks.

## [1.0.0] - 2026-09-02

### Added

- Added one persistent local-download workflow for URL drops, Add Link, Command-V inside an open notch, Downloader Settings, and connected YouTube media sources.
- Added explicit MP4, MP3, original-quality, resolution, and bitrate choices with structured progress, retry, cancellation, playlist confirmation, and completed shelf items.
- Added Automatic download selection as the default: YouTube Music and reliable audio-only metadata use MP3, while ambiguous YouTube content safely remains MP4. Job tiles provide one-time format overrides and playlists classify each item independently.
- Added display-aware drag routing based on live notch-window frames so shelf drops work across built-in and external displays.
- Added local MP4 compression through the separately installed FFmpeg engine, producing a safe H.264/AAC copy with cancellation and size reporting.
- Added bounded conversion of short MP4, MOV, and M4V videos into persistent GIF copies.

### Fixed

- Fixed sandboxed download promotion by resolving the authorized Downloads-directory symlink before validating staged output.
- Fixed Add Link popover lifetime, YouTube tab matching, actionable yt-dlp failures, collision-safe output handling, and download-result placement in the shelf.
- Preserved normal paste handling outside an open Nodebay notch and prevented duplicate jobs in multi-display mode.
- Fixed shelf drops from external volumes by retaining security-scoped access while bookmarks are created.
- Removed repeated Downloads-folder prompts by storing default downloads inside Nodebay and retaining one-time bookmarks for custom folders.
- Fixed PDF bullet glyphs appearing as `(cid:N)` placeholders in generated Markdown.
- Fixed generated Markdown disappearing during drag by storing it as a persistent regular file instead of a temporary file promise.

### Changed

- Updated the separately installed yt-dlp version recorded by diagnostics and notices to 2026.08.19.
- Declared yt-dlp and FFmpeg as Homebrew cask dependencies while keeping both engines unbundled and unmodified.
- Kept every conversion, compression, and download output collision-safe without modifying its source file.

## [0.1.2] - 2026-08-18

### Fixed

- Prevented the Nodebay Settings window from being restored or focused after launch, wake, or application activation unless the user explicitly opened it.

### Changed

- Documented the Homebrew 6 one-time trust requirement for casks from third-party taps.

## [0.1.1] - 2026-08-17

### Added

- Nodebay identity, original adaptive icon, About screen, and provider registry.
- Persistent file shelf, safe removal with Undo, File Stacks, multi-file drag, and Quick Look with Space.
- Local Microsoft MarkItDown document conversion with separate collision-safe outputs.
- Local yt-dlp and FFmpeg downloader workflow with completed items added to the shelf.
- Copy-first ImageOptim compression with results added beside source references.
- Media-source selection, system HUD replacement, and external-display placement modes.
- Optional first-party Chrome bridge for independently selecting and controlling YouTube and YouTube Music tabs.
- XPC-isolated processing, reproducible packaging, dependency-notice validation, and release checks.

### Changed

- User-facing product identity migrated from Boring Notch to Nodebay while retaining migration-safe internal identifiers.
- HUD interception now checks Accessibility for the signed main executable, recovers after event-tap disablement and lifecycle changes, and follows Nodebay's configured display placement.
- Unsupported volume, brightness, and keyboard-backlight events pass through to macOS instead of being swallowed.
- About Nodebay now links to the canonical source, releases, issues, license, acknowledgements, third-party notices, privacy policy, security policy, and Boring Notch upstream.

### Security

- External processes use structured arguments, allowlisted executables, bounded output, cancellation, and no shell interpolation.
- The browser bridge uses native messaging, loopback-only transport, a fixed control allowlist, and site access limited to YouTube and YouTube Music.

This is the first public Nodebay release.
