# Nodebay 1.2.1 for Apple Silicon

Nodebay 1.2.1 adds signed in-app updates and fixes media recovery, player spacing,
local Spotify equalizer routing and converter portability. Apple Silicon and
macOS 15 or later remain required.

- **Media recovery:** Now Playing starts without depending on a synthetic
  diagnostic player and restarts its helper after a failure. Media settings show
  actionable Automation errors and a Refresh Sources action.
- **Untitled audio:** active media without a supplied title, including shared
  audio from apps that publish a macOS media session, stays available as
  **Untitled media**. Empty sessions clear correctly, and another app's track
  details are not reused.
- **Player layout:** the original 640 × 190 notch size is preserved. Source tabs,
  metadata, progress and playback controls have their own space; optional lyrics
  share the artist row. EQ/download buttons no longer overlap custom
  playback controls; long control rows scroll.
- **Spotify equalizer:** Spotify desktop audio on the same Mac uses the native
  process EQ. An unmuted audio check keeps ordinary playback available until
  capture produces valid audio. The panel shows processing status, permission
  guidance and Retry; bypass or a processing failure restores normal playback.
- **Downloaded-copy setup:** System Audio Recording permission is required on
  each Mac. Media-control Automation permission is separate. See
  [equalizer setup](features/equalizer.md#set-up-a-downloaded-copy-on-another-mac).
- **Converter compatibility:** the bundled Python runtime now comes from the
  verified Python.org package instead of a Homebrew build requiring macOS 26.
  Release checks reject any bundled binary above the advertised macOS 15 minimum
  or dependent on a developer-local library.
- **Image compression:** optimized copies are saved in Nodebay's persistent
  storage, so read-only files and folders no longer require write access beside
  the original. Original files remain unchanged.
- **In-app updates:** check manually in About Nodebay, or choose automatic
  checks and downloads. Nodebay verifies its own signed feed and archives, and
  defers restart while downloads, conversions or drafts are active. Existing
  1.2.0 installations need one manual/Homebrew upgrade to gain this feature.
  See [update setup](features/updates.md).
- **Shelf preservation:** quitting waits for pending shelf saves; overlapping
  imports and conversions remain active until every operation finishes.

The clean build 28 package and [independent CI](https://github.com/Kian-hdr/nodebay/actions/runs/34404354725)
passed. The app and DMG are Developer ID signed, Apple-notarized and stapled;
the final ZIP and read-only DMG layout were verified. The full suite completed
with two optional tool checks skipped; all 19 final feed checks then passed
separately with the actual Sparkle tools. Exact results and hashes are in the
[verification matrix](release-verification-matrix.md).

Installed build 27 rejected a bad feed signature and a truncated archive before
installation. A real OpenAI API validation also passed, and Command-Q during
the request correctly kept Nodebay running. The complete 27 → 28 download,
installation and relaunch then passed through the separate testing feed using
the unchanged production archive. Afterward, the saved Keychain key completed
another real API validation without re-entry, and all 18 sampled managed files
remained unchanged. The installed executable matched the final production hash.

Authenticated Spotify playback, live EQ adjustment, bypass and pause/resume recovery passed in the compact installed candidate. Fresh capture-permission grant/denial, output-device switching and execution on a recipient's macOS 15 Mac remain untested. Process EQ handles local Mac audio; it does not equalize Spotify Connect playback on another device. Chrome EQ can affect other audible Chrome tabs.

Nodebay remains GPL-3.0 software based on Boring Notch. Required component notices
and source references are included in the repository and release packages.
