# Changelog

All notable Nodebay changes are recorded here. The project follows semantic versioning after its first public release.

## [Unreleased]

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

### Security

- External processes use structured arguments, allowlisted executables, bounded output, cancellation, and no shell interpolation.
- The browser bridge uses native messaging, loopback-only transport, a fixed control allowlist, and site access limited to YouTube and YouTube Music.

No public Nodebay version has been released yet.
