# Architecture

Nodebay is a native SwiftUI and AppKit macOS application. `BoringViewCoordinator` manages display windows; `BoringViewModel` owns shared presentation state; the shelf view model persists file references, stable stack identifiers, and security-scoped bookmarks.

Processing integrations implement the provider registry and expose status, version, privacy, supported types, and diagnostics to one Plugins & Engines settings destination. Document conversion, downloads, and compression become explicit jobs. External executables run outside the main UI through the XPC helper using structured argument arrays and allowlisted paths.

The media-source registry keeps independent static controllers and dynamically keyed browser-tab controllers, then selects one active target rather than merging unrelated sessions. A first-party Chrome content script reports compatible YouTube media state through Chrome native messaging. The native host forwards newline-delimited JSON over loopback to Nodebay. Commands are restricted to a fixed playback allowlist, and stale sessions are pruned. The display coordinator creates physical or virtual notch windows from shared state and prevents duplicated actions in all-display mode.

The MarkItDown runtime is generated reproducibly but excluded from Git. yt-dlp, FFmpeg, and ImageOptim are separately installed companions. Browser bridge 0.1.1 is first-party GPL-3.0 code bundled as source resources; Chrome still requires explicit unpacked-extension installation.
