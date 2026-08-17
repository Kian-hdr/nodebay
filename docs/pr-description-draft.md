# Pull request draft

Target: `TheBoredTeam/boring.notch:dev`  
Source: `Kian-hdr/boring.notch:feature/nodebay`

## Nodebay: local processing and persistent utility-bay foundations

This PR presents Nodebay, a downstream edition based on Boring Notch `dev` commit `44dd999f70493da48209c99e9f873c47f2e55c83`.

### What changed

- Rebrands the user-facing application as Nodebay while retaining the legacy bundle identifier for migration safety.
- Adds an original editable Icon Composer project and production icon assets.
- Adds About, Plugins & Engines, Converters, Downloader, Image Compression, Media Sources, and Display settings.
- Hardens local MarkItDown 0.1.7 conversion with XPC isolation, copy-safe collision handling, progress, errors, cancellation, and batch results.
- Adds persistent file stacks, multi-file AppKit drag sessions, reference-only removal, and Undo.
- Adds structured local yt-dlp and FFmpeg companion jobs without shell interpolation, browser-cookie access, or arbitrary arguments.
- Adds copy-first ImageOptim companion processing so source images are never optimized in place.
- Adds media-source and display registries with honest fallbacks where macOS cannot enumerate independent sources.
- Adds reproducible Apple Silicon builds, privacy checks, fixtures, dependency manifests, full notices, and Homebrew cask preparation.

### Safety and privacy

- Original shelf files are never overwritten, moved, or deleted.
- Generated outputs use collision-safe names.
- External engines run outside the main UI through an allowlisted XPC helper.
- MarkItDown conversion and image compression are local-only.
- Downloader traffic goes directly from the Mac to the requested source. Nodebay has no proxy, analytics endpoint, or download server.
- MarkItDown, yt-dlp, FFmpeg, and ImageOptim are not forked or modified.

### Verification

See `docs/nodebay-verification.md` for the exact passed, pending, and unavailable checks. The PR will not claim Gatekeeper acceptance until the final artifact is notarized and stapled.

### Licensing

Nodebay remains GPL-3.0. The exact Boring Notch foundation commit is recorded, MarkItDown 0.1.7 is attributed under MIT, and every bundled runtime dependency is covered by generated notices and a manifest check. yt-dlp, FFmpeg, and ImageOptim are detected companion installations and are not bundled.

### Screenshots

Final signed-build screenshots will be inserted here before publication.

