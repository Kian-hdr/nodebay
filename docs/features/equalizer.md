# Equalizer

Nodebay provides real five-band audio processing for these bounded source types:

- MP3, M4A, WAV, AIFF, and CAF files played from the Nodebay shelf with **Play in Nodebay**.
- QuickTime Player audio.
- Chrome audio while a connected YouTube or YouTube Music tab is selected in Nodebay.

The compact Equalizer panel uses a smooth, directly editable sound-response curve. Its three accessible handles adjust Bass, Mid, and Treble while the underlying five-band processor remains unchanged. The flat 0 dB line is visually centered, with boost above and reduction below. Dragging a handle updates the sound immediately and creates a Custom profile, while Reset returns the curve to flat. Internally, gains remain constrained to -12 through +6 dB, and Nodebay applies automatic negative headroom equal to the largest positive band gain to reduce clipping risk.

Local files use Apple's AVAudioEngine and AVAudioUnitEQ. QuickTime and Chrome use Apple's Core Audio process taps with `mutedWhenTapped`: the source's ordinary output remains intact until Nodebay's processing engine is reading, then Nodebay routes the equalized signal to the active output device. Stopping, bypassing, switching away, or a processing failure restores the source's ordinary audio path. No path sends audio to Nodebay servers or any other service, records it, or modifies the source file.

The browser bridge identifies and controls individual YouTube tabs. Chrome's audio renderer is process-scoped, however, so the native EQ can affect other Chrome audio playing at the same time. Nodebay shows this limitation rather than claiming per-tab sound isolation.

Apple Music, Spotify, and generic System Now Playing remain unavailable because Nodebay does not have a sufficiently specific, verified process target for those sources. The equalizer reports **Unavailable for this source** instead of displaying inert controls.

## Current limitations

- Local video-file playback is not part of this first equalizer release. Extracted or downloaded MP3/M4A audio is supported.
- Chrome EQ is process-scoped rather than isolated to one tab. Pause other Chrome tabs when you want only one tab processed.
- Process EQ requires macOS 14.2 or later and System Audio Recording permission.
- Audio-device changes cause the processing graph to rebuild. The source's ordinary output is restored during recovery.
