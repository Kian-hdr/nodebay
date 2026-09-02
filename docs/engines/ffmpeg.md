# FFmpeg

- Purpose: local media merge, transcode, audio extraction, and safe-copy MP4 compression
- Version: detected and tested Homebrew 9.0.1; not bundled
- Status: separately installed at `/opt/homebrew/bin/ffmpeg`
- Behavior: local processing with no Nodebay network use
- Inputs and outputs: formats selected through the downloader's bounded presets
- Permissions: read and write access to the active download directory
- Failure: the download job reports processing failure and retains safe completed intermediates where applicable
- Diagnostics: version, availability, exit status, and bounded stderr
- Source: https://ffmpeg.org
- License: detected Homebrew build is GPLv3+ because `--enable-gpl` and `--enable-version3` are active

The recorded build configuration is in `docs/ffmpeg-homebrew-9.0.1-configuration.txt`. FFmpeg does not endorse Nodebay.

Nodebay 1.0.0 adds [MP4 compression](../features/video-compression.md)
using the same approved XPC engine path, a local-file-only protocol allowlist,
H.264/AAC output, bounded threads, cancellation, and original-file preservation.
No extra binary or library is bundled for this feature.
