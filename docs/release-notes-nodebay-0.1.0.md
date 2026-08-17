# Nodebay 0.1.0 for Apple Silicon

Nodebay is a local-first utility bay for the MacBook notch and external displays. It is based on Boring Notch and distributed under GPL-3.0 as an independent project.

## Highlights

- Persistent file shelf and named File Stacks with multi-file Finder dragging
- Local PDF and DOCX conversion through unmodified Microsoft MarkItDown 0.1.7
- Structured local yt-dlp downloads with optional FFmpeg processing
- Copy-first ImageOptim integration that never sends the original image to ImageOptim
- Independent media-source selection and display-aware placement
- Optional first-party Chrome bridge for independently selecting compatible YouTube and YouTube Music tabs
- Provider diagnostics, process isolation, bounded logs, cancellation, and collision-safe outputs

## Privacy and file safety

Nodebay has no analytics endpoint, proxy, download server, or Nodebay cloud account. Document conversion and image compression run locally. Downloader requests go directly from the Mac to the selected source.

Nodebay never overwrites, moves, modifies, or deletes an original shelf file. Removing a tile removes only Nodebay's reference. Generated files are separate collision-safe copies.

## Requirements

- Apple Silicon Mac
- macOS 15 Sequoia or newer
- Optional separate companions: yt-dlp, FFmpeg, and ImageOptim

## Upgrade notes

The first Nodebay release deliberately retains the legacy `theboringteam.boringnotch` bundle identifier to preserve existing preferences, security-scoped bookmarks, shelf state, and permission continuity. The visible application and release assets are named Nodebay. A future bundle-identifier migration will require a separately tested upgrade path.

The historical Boring Notch repositories are retained privately as migration records. New users should install Nodebay 0.1.0 from the canonical Nodebay repository.

## Known limitations

- Individual browser-tab control currently requires explicit installation of the bundled Chrome extension and supports only `www.youtube.com` and `music.youtube.com`.
- Live multi-tab Chrome verification remains pending until the extension installation is approved.
- Some third-party media sources expose only the controls available through macOS or their local interfaces.
- yt-dlp, FFmpeg, and ImageOptim are not bundled.
- The final release must not be described as notarized or Homebrew-installable until those checks complete successfully.

## Provenance

Nodebay is based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) commit `44dd999f70493da48209c99e9f873c47f2e55c83`. Microsoft MarkItDown, yt-dlp, FFmpeg, ImageOptim, Apple, Spotify, YouTube, and other providers do not endorse or maintain Nodebay. Complete source, GPL-3.0 terms, dependency notices, privacy information, and reproducible build instructions are included.

Final SHA-256 checksums will be inserted only after notarization, stapling, and Gatekeeper verification.
