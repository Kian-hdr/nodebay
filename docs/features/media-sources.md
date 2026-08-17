# Media sources

Nodebay maintains independent media-source state for system Now Playing, Apple Music, Spotify, and supported YouTube Music integration. The source picker shows only available sources and routes controls to one selected target. It does not launch Spotify merely to query status, and unavailable controls are disabled.

Public macOS APIs cannot reliably enumerate every browser tab. The optional browser native-messaging bridge is not shipped, so Nodebay does not claim individual-tab selection. System Now Playing remains the fallback.
