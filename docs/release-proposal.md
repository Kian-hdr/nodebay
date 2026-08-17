# Nodebay 0.1.1 final publication proposal

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

## Root cause and proposed source update

The installed Developer ID build had a stable designated requirement, but macOS Accessibility still held an older ad-hoc CDHash. The running executable therefore failed `AXIsProcessTrusted()`, so Nodebay never created its modifying media-key event tap. The release detects that authorization change, presents one reauthorization path, monitors the current signed executable, and automatically recreates a missing or disabled event tap after wake, activation, and display changes.

The HUD now routes to Nodebay's configured display mode, passes unsupported controls through to macOS, exposes privacy-safe diagnostics, and retains the existing BetterDisplay and Lunar companion behavior for external brightness. About Nodebay links now use the canonical repository and `main` branch.

## Proposed release

- Tag: `nodebay-v0.1.1`
- Application version and build: `0.1.1 (2)`
- Application archive: `Nodebay-0.1.1-arm64.zip`
- Checksum file: `Nodebay-0.1.1-checksums.txt`
- Architecture: Apple Silicon
- Minimum macOS: 15.0
- Signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`

Apple accepted notarization submission `d75f3e51-238c-4e83-973f-cdfffcd16881`. The ticket is stapled, `spctl` reports `Notarized Developer ID`, and the final archive passes deep signature, hardened-runtime, timestamp, designated-requirement, architecture, version, notice, staple, and Gatekeeper checks.

Final SHA-256: `c497711aebcc549666f5f607e1c6c789d70c28d2636352ed918409f7197fb2a7`.

## Proposed Homebrew publication

Create public `Kian-hdr/homebrew-nodebay` with the reviewed `Casks/nodebay.rb` and README. The cask installs exactly `Nodebay.app`, uses the final notarized archive checksum, requires Apple Silicon and macOS 15, and preserves normal quarantine behavior.

```bash
brew tap Kian-hdr/nodebay
brew install --cask nodebay
```

The fully qualified equivalent is `brew install --cask Kian-hdr/nodebay/nodebay`.

## Obsolete repository visibility

- `Kian-hdr/homebrew-boring-notch-markitdown` can change directly from archived public to archived private.
- `Kian-hdr/boring.notch` is a public fork. GitHub requires it to leave the fork network before it can become private. Detachment is permanent, preserves Git commit metadata, and removes the fork relationship. The repository currently has no issues, pull requests, releases, child forks, stars, or watchers.

## Remaining gate

Review the exact commits, release text, artifact, checksum, Homebrew cask, results, and limitations, then obtain explicit approval immediately before public writes. No push, tag, release, tap creation, or Homebrew publication occurs before that approval.
