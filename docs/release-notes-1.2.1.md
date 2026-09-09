# Nodebay 1.2.1 for Apple Silicon

**UNPUBLISHED release candidate: final installer and publication checks are in progress.**
Nodebay 1.2.1 fixes media recovery, player spacing, local Spotify equalizer
routing and converter portability. Apple Silicon and macOS 15 or later remain
required.

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

- **In-app updates:** check manually in About Nodebay, or choose automatic checks and downloads. Nodebay verifies its signed feed and archives, and defers restart while downloads, conversions or drafts are active. Existing 1.2.0 installations require one final manual/Homebrew upgrade. See [update setup](features/updates.md).
- **Shelf preservation:** quitting waits for admitted shelf saves; overlapping imports and conversions remain active until every operation finishes.

The earlier build 26 bugfix candidate passed 222 tests and independent CI, and its application was notarized and stapled. Those artifacts are superseded by the updater-enabled build 28. Final source tests, package checks and real installed update acceptance are in progress and recorded in the [verification matrix](release-verification-matrix.md).

Authenticated Spotify playback, live EQ adjustment, bypass and pause/resume recovery passed in the compact installed candidate. Fresh capture-permission grant/denial, output-device switching and execution on a recipient's macOS 15 Mac remain untested. Process EQ handles local Mac audio; it does not equalize Spotify Connect playback on another device. Chrome EQ can affect other audible Chrome tabs.

Nodebay remains GPL-3.0 software based on Boring Notch. Required component notices
and source references are included in the repository and release packages.
