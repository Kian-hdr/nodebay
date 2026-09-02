# Nodebay 1.0.0 final publication proposal

This document records the complete local release candidate. It does not authorize external publication by itself.

## Destinations

- Canonical source and release: `https://github.com/Kian-hdr/nodebay`
- Stable branch: `main`
- Development branch: `dev`
- Homebrew tap: `https://github.com/Kian-hdr/homebrew-nodebay`
- Release tag: `nodebay-v1.0.0`
- Exact Boring Notch foundation: `44dd999f70493da48209c99e9f873c47f2e55c83`

## Source changes

The proposed source promotes the complete downloader and display-routing work, automatic audio-or-video selection with safe ambiguity fallback, per-item playlist classification, external-volume shelf access, safe MP4 compression, bounded video-to-GIF conversion, durable generated Markdown and GIF storage, corrected PDF bullets, release documentation, and the 1.0.0 cask.

The existing commit history remains intact. The proposed commits beyond public `main` are:

1. `1de9b43` Fix shelf tab switching while dragging content
2. `b932f81` Add hardened local downloads and display-aware routing
3. `9169c6d` Document downloader behavior and engine requirements
4. `8114a71` Install the pinned runtime in CI
5. `5dcf453` Add runtime verification tools to CI
6. `dcd637b` Update CI for Swift 6.2
7. `9af365a` Retain external-volume drag access
8. `5e44f12` Add safe video processing and durable generated outputs
9. `1b29e7b` Prepare the Nodebay 1.0.0 documentation and version metadata
10. `6f5102f` Choose media type automatically with safe classification and overrides
11. Final release-evidence commit containing the DMG cask, verification matrix, and publication proposal

The unrelated untracked drafts `docs/proposals/video-to-gif.md` and `docs/release-proposal 2.md` are explicitly excluded.

## Primary release artifact

- File: `Nodebay-1.0.0-arm64.dmg`
- Version and build: `1.0.0 (21)`
- Architecture: Apple Silicon arm64
- Minimum macOS: 15.0 Sequoia
- Size: 86,731,065 bytes
- SHA-256: `e33c60cbcf7aa2b80780b8f8c285e051fa94afe21f0b8db7cdaea9d8e0d4e772`
- Signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`
- Apple notarization: accepted, submission `3cf0388f-b757-49f2-a7e2-657887e62aab`
- Stapling and Gatekeeper: passed
- DMG layout: `Nodebay.app` and Applications shortcut, plus hidden Finder presentation metadata

The DMG was verified, mounted read-only, installed into `/Applications`, and launched. The installed application reports 1.0.0 build 21. Only one installed Nodebay app and no installed Boring Notch app were found.

## Homebrew publication

The cask installs only `Nodebay.app`, requires Apple Silicon and macOS Sequoia, verifies the final DMG checksum, and installs unmodified yt-dlp and FFmpeg as formula dependencies. It preserves the current migration-safe bundle identifier and user data.

```ruby
cask "nodebay" do
  version "1.0.0"
  sha256 "e33c60cbcf7aa2b80780b8f8c285e051fa94afe21f0b8db7cdaea9d8e0d4e772"

  url "https://github.com/Kian-hdr/nodebay/releases/download/nodebay-v#{version}/Nodebay-#{version}-arm64.dmg"
  name "Nodebay"
  desc "Local-first utility bay for the MacBook notch and external displays"
  homepage "https://github.com/Kian-hdr/nodebay"

  livecheck do
    url :url
    regex(/^nodebay-v?(\d+(?:\.\d+)+)$/i)
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on formula: "yt-dlp"
  depends_on formula: "ffmpeg"

  app "Nodebay.app"

  uninstall quit: "theboringteam.boringnotch"

  zap trash: [
    "~/Library/Application Support/Nodebay",
    "~/Library/Caches/theboringteam.boringnotch",
    "~/Library/Preferences/theboringteam.boringnotch.plist",
  ]
end
```

After publication, both commands will be tested against the public asset:

```bash
brew tap Kian-hdr/nodebay
brew install --cask nodebay
```

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

## Verification and limitations

Automated tests, Debug and Release builds, signing, notarization, stapling, Gatekeeper, local PDF and DOCX conversion, local downloader, ImageOptim safe-copy processing, repository validation, notice validation, and the installed-app launch passed. The complete evidence classification is in `docs/release-verification-matrix.md`.

Physical media-key, external-monitor, external-SSD, context-menu, multi-tab browser bridge, accessibility, and stress tests were not rerun on the final 1.0.0 binary. Prior user demonstrations and automated contracts are recorded separately and are not presented as current physical verification. Homebrew online audit, clean install, and upgrade can run only after the release URL exists.

## Approval gate

No commit push, branch update, tag, GitHub release, asset upload, or public Homebrew change occurs until the repository owner reviews this package and gives explicit final publication approval.
