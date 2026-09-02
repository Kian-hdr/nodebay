# Nodebay 1.0.0 for Apple Silicon

Nodebay 1.0.0 is the first stable release line for the expanded local-first utility bay.

## New features

- Download YouTube and other supported media links through drag and drop, Add Link, Command-V inside an open notch, or a connected YouTube media source.
- Choose MP4, MP3, best original quality, resolution, or bitrate, with retry, cancellation, playlist confirmation, and completed files added to the shelf.
- Automatic is now the recommended default: YouTube Music and reliable structured music metadata select MP3, ambiguous YouTube content preserves video as MP4, and each playlist item is classified independently. A format control on the job tile provides one-time Video, Audio, or Best Original overrides.
- Compress local MP4 files into separate H.264/AAC copies through a separately installed FFmpeg engine.
- Convert short MP4, MOV, and M4V videos into persistent GIF copies.

## Fixes

- File and URL drags now route to the correct notch on built-in and external displays.
- Files from external SSDs retain their security-scoped access when added to the shelf.
- Nodebay no longer requests broad Downloads-folder access whenever a file is dragged.
- PDF bullet glyphs no longer appear as `(cid:N)` placeholders in generated Markdown.
- Generated Markdown and GIF files remain available as regular draggable files instead of disappearing temporary file promises.
- Downloader output validation, YouTube tab matching, Add Link popover behavior, collision handling, and actionable failures were repaired.

## Privacy and file safety

Document conversion and media processing remain local. Downloads connect directly from the Mac to the selected source. Nodebay does not operate a proxy, analytics endpoint, or download server. Original shelf files are never overwritten, moved, or deleted.

yt-dlp and FFmpeg remain separately installed, unmodified Homebrew companions. Microsoft MarkItDown 0.1.7 remains bundled unmodified under the MIT License.

## Installation

```bash
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
```

Existing users can run:

```bash
brew update
brew upgrade --cask nodebay
```

Nodebay 1.0.0 retains the migration-safe bundle identifier, preferences, shelf state, bookmarks, and Accessibility identity.
