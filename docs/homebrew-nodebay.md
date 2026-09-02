# Homebrew distribution

Nodebay is distributed as an Apple Silicon cask through `Kian-hdr/homebrew-nodebay`.

## Installation

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

The cask installs only `Nodebay.app` into `/Applications` from the signed and notarized DMG, and verifies the DMG SHA-256. It requires Apple Silicon and macOS Sequoia or newer because the current MediaRemoteAdapter foundation binary has a macOS 15.0 minimum.

## Reproducible artifact

```bash
./scripts/package_homebrew_arm64.sh
```

The script rebuilds and tests the pinned MarkItDown 0.1.7 runtime, performs a clean Release build outside file-provider storage, validates the Apple Silicon application and runtime, and produces a ZIP plus SHA-256 file under `build/nodebay-homebrew-arm64-release/`. The release process then uses the pinned `Configuration/dmg` tooling to create the public DMG. Local builds use an ad-hoc signature by default.

For a public candidate, provide the installed Developer ID identity and team:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
./scripts/package_homebrew_arm64.sh
```

This signs the application, XPC service, frameworks, nested updater tools, MediaRemoteAdapter client, and bundled MarkItDown Mach-O components with the hardened runtime and secure timestamps. The DMG is separately Developer ID signed, submitted to Apple, stapled, and Gatekeeper assessed.

Before public distribution, verify the final cask checksum and download URL, notarize and staple the DMG, mount and install it, and rerun the complete release checklist. Publication requires the repository owner's explicit final approval.

## Dependencies

MarkItDown is bundled. The cask declares yt-dlp and FFmpeg as separate Homebrew formula dependencies. ImageOptim remains a separately installed companion application. Nodebay does not bundle or modify those three companions.

## Migration and uninstall

Nodebay deliberately retains the legacy Boring Notch bundle identifier for this first migration-safe release. This preserves preferences, bookmarks, saved shelf state, and Accessibility authorization. The visible app and artifact names are Nodebay. A future bundle-identifier migration requires a signed migration plan and compatibility tests.

Removing Nodebay does not delete original shelf files or downloaded media. Homebrew `zap` data removal is optional and must be initiated explicitly by the user.
