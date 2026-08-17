# Pull request draft

Target: `Kian-hdr/nodebay:main`
Source: `Kian-hdr/nodebay:dev`

## Release Nodebay 0.1.0

This pull request promotes the verified Nodebay 0.1.0 source from `dev` to the stable `main` branch. The new repository is standalone, not a GitHub fork, while preserving the complete reachable Boring Notch and Nodebay commit history.

### Repository and documentation

- Publishes public source, clone, release, Homebrew, support, and security URLs under `Kian-hdr/nodebay`.
- Replaces inherited community files with Nodebay-specific privacy-safe contribution, issue, pull-request, support, security, conduct, and release guidance.
- Preserves explicit Boring Notch attribution and the exact foundation commit `44dd999f70493da48209c99e9f873c47f2e55c83`.
- Retains the legacy application bundle identifier for the first migration-safe release.

### Release infrastructure

- Removes inherited publication workflows that target Boring Notch appcasts, Crowdin, Pages, and Homebrew repositories not controlled by Nodebay.
- Adds Apple Silicon CI for tests, notices, MarkItDown fixtures, downloader fixtures, cask syntax, and a clean Release build.
- Adds a manual, confirmation-gated Developer ID, notarization, verification, and optional GitHub release workflow.
- Uses Nodebay release names and checksum files consistently.

### Safety, privacy, and licensing

- Original user files remain immutable and shelf removal remains reference-only.
- MarkItDown 0.1.7 is bundled unmodified and operates locally.
- yt-dlp, FFmpeg, and ImageOptim remain separately installed companions.
- Generated outputs use collision-safe names.
- Complete GPL-3.0 provenance and third-party notices remain included and automatically checked.

### Verification

See `docs/nodebay-verification.md` and `docs/github-migration-preflight.md` for passed, pending, unavailable, and approval-gated checks.

### Publication boundary

Creating this PR does not authorize merging, notarization, releasing, Homebrew publication, or changes to upstream Boring Notch. Those remain separately approval-gated operations.
