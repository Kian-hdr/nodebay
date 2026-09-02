# Changelog

All notable Nodebay changes are recorded here. The project follows semantic versioning after its first public release.

## [Unreleased]

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
