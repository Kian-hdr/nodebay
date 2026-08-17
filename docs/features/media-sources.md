# Media sources

Nodebay maintains independent media-source state for system Now Playing, Apple Music, Spotify, the YouTube Music companion, and each connected compatible Chrome tab. The source picker routes controls to exactly one selected target. It does not merge unrelated playback sessions, launch Spotify merely to query status, or enable unsupported controls.

Public macOS APIs cannot reliably enumerate every browser tab. Nodebay therefore includes an optional first-party Chrome extension and local native bridge for `youtube.com` and `music.youtube.com`. Each tab containing playable media appears separately with its title, service, availability, and playback state. Selecting it makes that tab the active play, pause, seek, and volume target. Next and previous are enabled only when the page exposes those controls.

Extension installation and the two-site permission are explicit. If the extension disconnects or the selected tab closes, Nodebay removes the stale session and returns to the configured system media source. Unsupported browsers and sites continue to use system Now Playing.
