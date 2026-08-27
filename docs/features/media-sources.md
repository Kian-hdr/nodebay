# Media sources

Nodebay maintains independent media-source state for system Now Playing, Apple Music, Spotify, the YouTube Music companion, and each connected compatible Chrome tab. The source picker routes controls to exactly one selected target. It does not merge unrelated playback sessions, launch Spotify merely to query status, or enable unsupported controls.

Public macOS APIs cannot reliably enumerate every browser tab. Nodebay therefore includes an optional first-party Chrome extension and local native bridge for `youtube.com` and `music.youtube.com`. Each tab containing playable media appears separately with its title, service, availability, and playback state. Selecting it makes that tab the active play, pause, seek, and volume target. Next and previous are enabled only when the page exposes those controls.

Extension installation and the two-site permission are explicit. If the extension disconnects or the selected tab closes, Nodebay removes the stale session and returns to the configured system media source. Unsupported browsers and sites continue to use system Now Playing.

Now Playing shows a download control for a connected YouTube or YouTube Music tab and for Chrome media reported through System Now Playing. Nodebay first matches a unique browser-bridge session by title. If necessary, pressing Download performs a local, user-initiated Apple Event query for YouTube tab titles and URLs and accepts only one matching tab. It then sends that URL to the normal downloader and switches to the shelf so format selection and progress remain visible. The control is hidden for Apple Music, Spotify, and sources that cannot be resolved safely.
