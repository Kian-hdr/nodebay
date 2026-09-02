# Nodebay 1.1.0

The utility bay in your Mac's notch. Apple Silicon, macOS 15 or later.

## New features

- **Quick Notes:** explicitly paste text in the open shelf or use New Note to create a persistent Markdown file locally. File URLs still use the file workflow; URL-only text uses the downloader. Prose mixed with links remains a note. No continuous clipboard monitoring, AI processing or content logs.
- **Native Markdown Quick Look:** select `.md` or `.markdown` in Finder and press Space. Selectable headings, lists, tables and fenced code use system typography and the native translucent Quick Look background. Works with Nodebay quit.
- **STL Repair:** conservative Safe, confirmed Thorough and Inspect modes using the separately installed, unmodified Blender 5.0.1. Originals stay unchanged; batch results preserve partial successes. This is not a printability guarantee.

## Improvements and fixes

- Automatic downloads use source URLs and structured metadata, not titles alone. Ambiguous content remains video. Tiles show Audio/MP3 or Video/MP4 and offer an override.
- Playlist items retain individual classification; cancellation preserves completed outputs and stale progress cannot replace a newer attempt.
- MP3 extraction is unavailable without FFmpeg. yt-dlp and FFmpeg remain separate Homebrew dependencies.
- Hardened release packaging signs the Markdown extension and every nested executable, checks extension identity/version and excludes network access from previews.
- Homebrew `--zap` no longer removes the entire Nodebay Application Support directory. Normal uninstall and shelf removal do not delete saved outputs.

Existing file stacks, multi-file dragging, PDF/DOCX conversion, image-copy compression, MP4 compression, video-to-GIF, media controls, HUD and external-display routing remain included.

## Requirements and limits

- ImageOptim is optional and separately installed for image compression. Blender is optional and separately installed for STL repair. Neither is installed by the Nodebay cask.
- Downloads connect directly to the source service. Site support depends on yt-dlp and the service; cookies remain off by default. Users are responsible for rights and service terms.
- Quick Notes accepts 1 MiB of text. Hover-paste needs Accessibility and a pointer inside an open notch; New Note is the fallback. Automated routing/storage tests passed, but physical built-in/external hover-paste and destination-app dragging have not been fully reverified.
- Markdown previews accept up to 2 MiB, with bounded plain-text fallback above 256 KiB. Images become alt text; links are copyable but do not navigate. No remote resources load.
- STL repair has bounded input/resource limits and does not repair self-intersections. Inspect results before manufacturing; no physical print qualification is claimed.
- Finder preview was exercised on macOS 26.6.2 in light/dark appearance, with Nodebay quit. Other supported OS versions, a full VoiceOver audit, hardware HUD keys, wake/clamshell and the complete external-display matrix were not rerun for this release.
- External-monitor brightness requires compatible hardware/providers. Browser-tab media control requires explicit Chrome bridge installation. No Sparkle feed is configured; use Homebrew or manual upgrades.

## Install or upgrade

```sh
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
# Existing installation:
brew upgrade --cask Kian-hdr/nodebay/nodebay
```

The one-time trust command is required by Homebrew 6 for third-party casks. Alternatively install the release's `Nodebay.app` from the DMG or ZIP. Preserve the existing stable bundle identifier and Developer ID requirement to retain preferences and authorization; no TCC database changes are made.

Created by Kian Konrad Tajbakhsh. GPL-3.0, based on Boring Notch commit `44dd999f70493da48209c99e9f873c47f2e55c83`. Engine notices and corresponding-source instructions ship inside the app and in this repository. No provider endorsement is implied.

See [verification](https://github.com/Kian-hdr/nodebay/blob/main/docs/release-verification-matrix.md), [privacy](https://github.com/Kian-hdr/nodebay/blob/nodebay-v1.1.0/PRIVACY.md), [notices](https://github.com/Kian-hdr/nodebay/blob/nodebay-v1.1.0/THIRD_PARTY_NOTICES.md) and [build instructions](https://github.com/Kian-hdr/nodebay/blob/nodebay-v1.1.0/docs/release-process.md).
