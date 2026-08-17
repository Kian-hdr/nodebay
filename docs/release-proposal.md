# Nodebay 0.1.0 current release proposal

This document records the current state and remaining approval-gated work. It does not authorize external publication by itself.

## Completed repository migration

- Canonical standalone source: `https://github.com/Kian-hdr/nodebay`
- Visibility: public
- Stable branch: `main`
- Development branch: `dev`
- Exact Boring Notch foundation: `44dd999f70493da48209c99e9f873c47f2e55c83`
- Public release tags and releases: none
- Public Homebrew tap: not created
- Obsolete repositories: archived and still public pending the requested visibility change

## Proposed source update

Publish the reviewed browser-media feature commits to `dev`, open a release pull request from `dev` to `main`, and merge only after the checks and final copy are approved. The update adds an optional first-party Chrome bridge for independently selecting compatible YouTube and YouTube Music tabs. It does not modify or fork any processing engine.

## Proposed release

- Tag: `nodebay-v0.1.0`
- Application archive: `Nodebay-0.1.0-arm64.zip`
- Checksum file: `Nodebay-0.1.0-checksums.txt`
- Architecture: Apple Silicon
- Minimum macOS: 15.0
- Signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`

The exact Developer ID candidate must be submitted to Apple, notarized, stapled, re-zipped, and verified before its final SHA-256 can be placed in the Homebrew cask. No unnotarized archive should be advertised as the public Homebrew release.

Current pre-notarization candidate SHA-256: `94a49fe621eaf1d1b9fa5dedabeca56d17dd3e294b2308d2ff71f44593c3ce47`. This value will change after stapling and re-zipping.

## Proposed Homebrew publication

Create public `Kian-hdr/homebrew-nodebay` with the reviewed `Casks/nodebay.rb` and README. The cask must install exactly `Nodebay.app`, use the final notarized archive checksum, require Apple Silicon and macOS 15, and preserve normal quarantine behavior.

```bash
brew tap Kian-hdr/nodebay
brew install --cask nodebay
```

The fully qualified equivalent is `brew install --cask Kian-hdr/nodebay/nodebay`.

## Obsolete repository visibility

- `Kian-hdr/homebrew-boring-notch-markitdown` can change directly from archived public to archived private.
- `Kian-hdr/boring.notch` is a public fork. GitHub requires it to leave the fork network before it can become private. Detachment is permanent, preserves Git commit metadata, and removes the fork relationship. The repository currently has no issues, pull requests, releases, child forks, stars, or watchers.

## Remaining gates

1. Explicit confirmation for Chrome extension installation and live multi-tab verification.
2. Apple notarization credentials or an already configured `notarytool` profile.
3. Final post-notarization archive verification and SHA-256 calculation.
4. Final review of the tag, release notes, cask, social-preview upload, repository visibility changes, and public destinations.
5. Explicit approval immediately before public writes and access changes.
