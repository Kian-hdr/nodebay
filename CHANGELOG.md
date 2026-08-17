# Changelog

All notable Nodebay changes are recorded here. The project follows semantic versioning after its first public release.

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
