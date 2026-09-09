# Media sources

Nodebay maintains independent media-source state for system Now Playing, Apple Music, Spotify, QuickTime Player, the YouTube Music companion, and each connected compatible Chrome tab. A compact horizontal source strip routes controls to exactly one selected target. The selected source has a checkmark; the row scrolls when needed, and browser tabs use their media titles so they can be distinguished. A six-point gap separates the strip from the current title.

Only available media sessions appear. Closed apps and running apps without media are omitted, while paused sessions remain selectable. When a source disappears, selection moves to another available session or clears to **Nothing playing**. Empty playback state has no fabricated title, artist, or album. Unavailable integrations can still be inspected in Media settings. A generic system entry is omitted when it duplicates one uniquely identified, directly controllable session. Unrelated sessions and ambiguous browser-tab matches stay separate.

QuickTime Player is a dedicated local source because its local-file playback is not consistently published through macOS System Now Playing. Nodebay reads the front window's document through QuickTime's public scripting interface, preferring a playing document when several are open, and exposes play, pause, seek, and volume controls. Snapshot and command scripts use the same target-selection rule. QuickTime's bundle identifier is supplied to Nodebay's local audio capture for the animated waveform and, on macOS 14.2 or later, to its native Core Audio process equalizer for audible EQ presets. No filename, playback metadata, or audio is sent off the Mac.

Public macOS APIs cannot reliably enumerate every browser tab. Nodebay therefore includes an optional first-party Chrome extension and local native bridge for `youtube.com` and `music.youtube.com`. Each tab containing playable media appears separately with its title, service, availability, and playback state. Selecting it makes that tab the active play, pause, seek, and volume target. Next and previous are enabled only when the page exposes those controls.

Extension installation and the two-site permission are explicit. If the extension disconnects or the selected tab closes, Nodebay removes the stale session and selects an available remaining source. The native Chrome equalizer is process-scoped, so it can affect more than one audible Chrome tab even though media controls remain targeted at the selected tab. Unsupported browsers and sites continue to use system Now Playing.

Now Playing shows a download control for a connected YouTube or YouTube Music tab and for Chrome media reported through System Now Playing. Nodebay first matches a unique browser-bridge session by title. If necessary, pressing Download performs a local, user-initiated Apple Event query for YouTube tab titles and URLs and accepts only one matching tab. It then sends that URL to the normal downloader and switches to the shelf so format selection and progress remain visible. The control is hidden for Apple Music, Spotify, and sources that cannot be resolved safely.

## Recovery and recipient-Mac setup in 1.2.1

Media discovery starts immediately and retries after its helper exits. A synthetic diagnostic self-test no longer permanently disables the Now Playing source. App-specific Automation failures appear in Settings > Media with a Refresh Sources action; permission decisions are separate on each Mac. A current full snapshot clears stopped sessions, while transient helper failures get bounded recovery.

The pinned MediaRemoteAdapter v0.7.7 supports real active clients without a title, including untagged audio shared in chat apps. Nodebay displays Untitled media and preserves a paused session only when it belongs to the same known client. Empty or incomplete client snapshots still clear the source. It never manufactures a track title.

The player retains its original 640 × 190 notch size. Intrinsic rows separate tabs, metadata, timeline and controls; optional lyrics share the artist row. EQ/download accessories occupy their own toolbar space; long custom control rows scroll instead of overlapping them.

## Historical local verification, 2026-09-06

- All 197 repository tests passed. Compiled behavioral harnesses cover empty/closed sources, paused sessions, source fallback, exact and ambiguous browser identities, and cross-app metadata updates. QuickTime's five concrete scripts passed native AppleScript compilation without executing playback commands.
- The Developer ID arm64 Release build passed and was installed locally as 1.2.0 (25). Deep strict signature verification passed, the designated requirement was retained, and built/installed binary hashes matched.
- Native inspection on macOS 26.6.2 showed one selected QuickTime source, the six-point gap, no unavailable integrations or fabricated title, and an advancing playback timeline. Clicking the live source retained selection and playback. Both paused and playing layouts were inspected during the change.
- Individual browser-tab switching, overflow, source closure/empty state, other OS versions, VoiceOver, accessibility-setting combinations, and performance profiling were not exercised in the final installed UI. The Browser Media Bridge was disconnected; per-tab controls still require its existing explicit setup. Playback commands were compile-tested, not exercised against the user's playing video.
- The advisory design audit retained existing findings. Live Apple resource-manifest validation passed. The initial signing failure was resolved by removing prohibited Finder metadata from generated build products only.

Local evidence: `build/verification/media-tabs-20260906/`. This is local development verification, not a release or notarization claim.
