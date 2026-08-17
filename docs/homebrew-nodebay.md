# Homebrew distribution

Nodebay is prepared as an Apple Silicon cask. It is not published yet.

## Proposed installation

After a signed or explicitly approved public release and tap are created, the intended command is:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

The cask installs `Nodebay.app` into `/Applications` and verifies the release archive SHA-256. It requires Apple Silicon and macOS Sequoia or newer because the current MediaRemoteAdapter foundation binary has a macOS 15.0 minimum.

## Reproducible artifact

```bash
./scripts/package_homebrew_arm64.sh
```

The script rebuilds and tests the pinned MarkItDown 0.1.7 runtime, performs a clean Release build outside file-provider storage, validates both arm64 executables, and produces a ZIP plus SHA-256 file under `build/nodebay-homebrew-arm64-release/`. It uses an ad-hoc signature by default for local verification.

For a public candidate, provide the installed Developer ID identity and team:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVELOPMENT_TEAM="TEAMID" \
./scripts/package_homebrew_arm64.sh
```

This signs the application, XPC service, and bundled MarkItDown Mach-O components with the hardened runtime. Notarization and stapling remain separate approval-gated release steps.

Before public distribution, verify the final cask checksum and download URL, notarize and staple the app, and rerun the complete release checklist. Publication requires the repository owner's explicit final approval.

## Dependencies

MarkItDown is bundled. yt-dlp and FFmpeg are separate Homebrew companion tools. ImageOptim is a separately installed companion application. Nodebay does not bundle those three companions in the current packaging model.

## Migration and uninstall

Nodebay deliberately retains the legacy Boring Notch bundle identifier for this first migration-safe release. This preserves preferences, bookmarks, saved shelf state, and Accessibility authorization. The visible app and artifact names are Nodebay. A future bundle-identifier migration requires a signed migration plan and compatibility tests.

Removing Nodebay does not delete original shelf files or downloaded media. Homebrew `zap` data removal is optional and must be initiated explicitly by the user.
