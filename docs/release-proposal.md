# Nodebay 0.1.0 publication proposal

This document is a draft only. It does not authorize any external action.

## Proposed destinations

- Source fork: `https://github.com/Kian-hdr/boring.notch`
- Branch: `feature/nodebay`
- Upstream issue: `https://github.com/TheBoredTeam/boring.notch/issues/new`
- Upstream PR target: `TheBoredTeam/boring.notch:dev`
- Release tag: `nodebay-v0.1.0`
- Proposed tap: `https://github.com/Kian-hdr/homebrew-nodebay`
- Proposed install command: `brew install --cask Kian-hdr/nodebay/nodebay`

## Proposed release assets

- `Nodebay-0.1.0-arm64.zip`
- `Nodebay-0.1.0-arm64.zip.sha256`
- GPL-3.0 source at the exact release tag
- Complete notices and privacy documentation inside the application archive and source tree

Current pre-notarization candidate SHA-256: `3e073e3311159047246cc8de39810dd6b6506cfd8c1172287291dddde74183c1`.

Current signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`.

Notarization result, staple verification, screenshots, final commit list, and cask audit result must be inserted after those checks are complete. Notarization changes the distributed application and therefore requires a final post-notarization archive and checksum.

## Proposed release title

Nodebay 0.1.0 for Apple Silicon

## Proposed release notes

Nodebay is a local-first utility bay for the MacBook notch and external displays, based on Boring Notch.

This first Apple Silicon release includes persistent file stacks, safe local document-to-Markdown conversion through Microsoft MarkItDown 0.1.7, local companion workflows for yt-dlp, FFmpeg, and ImageOptim, configurable media sources, and multi-display placement.

Original user files are never overwritten or deleted by shelf removal or processing. Generated outputs are separate collision-safe copies. MarkItDown is bundled and runs locally. yt-dlp, FFmpeg, and ImageOptim remain separate companion installations.

Requirements: Apple Silicon and macOS 15 Sequoia or newer.

Nodebay is GPL-3.0 software based on Boring Notch. Complete source, foundation attribution, third-party notices, privacy information, and build instructions are included.

## Approval gate

Before any fork, push, issue, release, tap, or pull request is created, present the final diff, commits, signed/notarized artifact hashes, screenshots, notices, verification matrix, destinations, issue text, PR text, release notes, and Homebrew cask to the repository owner and obtain explicit final approval.
