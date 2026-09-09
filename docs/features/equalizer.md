# Equalizer

Nodebay provides real five-band audio processing for these bounded source types:

- MP3, M4A, WAV, AIFF, and CAF files played from the Nodebay shelf with **Play in Nodebay**.
- QuickTime Player audio.
- Spotify desktop audio playing on the same Mac as Nodebay, including Spotify audio helpers.
- Chrome audio while a connected YouTube or YouTube Music tab is selected in Nodebay.

The compact Equalizer panel uses a smooth, directly editable sound-response curve. Its three accessible handles adjust Bass, Mid, and Treble while the underlying five-band processor remains unchanged. The flat 0 dB line is visually centered, with boost above and reduction below. Dragging a handle updates the sound immediately and creates a Custom profile, while Reset returns the curve to flat. Internally, gains remain constrained to -12 through +6 dB, and Nodebay applies automatic negative headroom equal to the largest positive band gain to reduce clipping risk.

Local files use Apple's AVAudioEngine and AVAudioUnitEQ. Spotify, QuickTime and Chrome use Apple's Core Audio process taps. Nodebay first checks an **unmuted** tap while keeping its own output silent. Only after receiving valid, nonzero audio samples does it switch to `mutedWhenTapped` and route the equalized signal to the active output device. A callback that receives only zeros, including when macOS has not supplied capture access, does not mute the source. Stopping, bypassing, switching away, a stalled callback, or a processing failure restores the source's ordinary audio path. If received audio goes silent, Nodebay restores ordinary output after one second and briefly checks for audio to resume. No path sends audio to Nodebay servers or any other service, records it, or modifies the source file.

The browser bridge identifies and controls individual YouTube tabs. Chrome's audio renderer is process-scoped, however, so the native EQ can affect other Chrome audio playing at the same time. Nodebay shows this limitation rather than claiming per-tab sound isolation.

Apple Music and unidentified System Now Playing sources remain unavailable because Nodebay does not have a sufficiently specific process target for those sources. A system Now Playing source identified as Spotify, QuickTime or Chrome uses that supported app’s process target. The equalizer reports **Unavailable for this source** for unsupported apps. For supported apps it shows the actual processing state, including audio-access checks and actionable failure messages, with **Retry** and **Audio Recording Settings** recovery actions.

## Current limitations

- Local video-file playback is not part of this first equalizer release. Extracted or downloaded MP3/M4A audio is supported.
- Chrome EQ is process-scoped rather than isolated to one tab. Pause other Chrome tabs when you want only one tab processed.
- Nodebay requires macOS 15 or later. Process EQ uses APIs available since macOS 14.2 and requires System Audio Recording permission on each Mac.
- Changes to the output device, its sample rate, or the source’s audio helper processes cause the processing graph to rebuild. The source’s ordinary output is restored and the new route is checked before processing resumes.
- Process EQ applies only to audio emitted on the Mac running Nodebay. It does not process Spotify Connect playback on a remote speaker/device.
- Protected audio or a device with an unsupported channel/format layout can remain unavailable. Nodebay preserves normal playback and reports the failure.


## Set up a downloaded copy on another Mac

1. Install the signed Nodebay app in Applications and open that copy.
2. Start Spotify or QuickTime playback on that Mac, select its source in Nodebay and open Equalizer.
3. Allow macOS’s System Audio Recording request. A permission granted on the developer’s Mac is not transferred in a GitHub download.
4. If the panel says no audio was received, open **Audio Recording Settings**, enable Nodebay under **Privacy & Security > Screen & System Audio Recording**, and follow any macOS restart instruction. Resume playback and choose **Retry**.
5. Media metadata/control can separately require **Automation** permission for Spotify or QuickTime. Equalizer capture permission and Automation permission are different.

## Verification boundaries

The regression harness executes the production Core Audio DSP against a 1 kHz signal, checks live gain updates, both interleaved and separate-channel buffer layouts, and failure/passthrough behavior. Identity and health-policy tests cover Spotify/helper matching, unrelated processes, zero-filled callbacks, stale callbacks and unsupported layouts. These deterministic checks do not establish audible Spotify playback, macOS permission acceptance, Bluetooth/AirPlay performance, or operation on a recipient’s physical Mac. Final installed-app observations belong in the release verification matrix.

Apple documents [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) and the mutable [tap description](https://developer.apple.com/documentation/coreaudio/kaudiotappropertydescription) used by this pipeline. No private TCC API or permission bypass is used.
