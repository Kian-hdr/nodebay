# Homebrew distribution

Nodebay is prepared as an Apple Silicon cask. It is not published yet.

## Proposed installation

After a signed or explicitly approved public release and tap are created, the intended command is:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

The cask installs `Nodebay.app` into `/Applications` and verifies the release archive SHA-256. It requires Apple Silicon and macOS Sonoma or newer.

## Reproducible artifact

```bash
./scripts/package_homebrew_arm64.sh
```

The script rebuilds and tests the pinned MarkItDown 0.1.7 runtime, performs a clean Release build, stages Nodebay outside file-provider storage, applies an ad-hoc signature for local testing, validates both arm64 executables, and produces a ZIP plus SHA-256 file under `build/nodebay-homebrew-arm64-release/`.

Before public distribution, replace `VERSION` and `SHA256` in `Casks/nodebay.rb.template`, verify the final download URL, sign and notarize the app, and rerun the complete release checklist. Publication requires the repository owner's explicit final approval.

## Dependencies

MarkItDown is bundled. yt-dlp and FFmpeg are separate Homebrew companion tools. ImageOptim is a separately installed companion application. Nodebay does not bundle those three companions in the current packaging model.

## Migration and uninstall

Nodebay deliberately retains the legacy Boring Notch bundle identifier for this first migration-safe release. This preserves preferences, bookmarks, saved shelf state, and Accessibility authorization. The visible app and artifact names are Nodebay. A future bundle-identifier migration requires a signed migration plan and compatibility tests.

Removing Nodebay does not delete original shelf files or downloaded media. Homebrew `zap` data removal is optional and must be initiated explicitly by the user.
