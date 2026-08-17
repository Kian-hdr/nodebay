# Architecture

Nodebay is a native SwiftUI and AppKit macOS application. `BoringViewCoordinator` manages display windows; `BoringViewModel` owns shared presentation state; the shelf view model persists file references, stable stack identifiers, and security-scoped bookmarks.

Processing integrations implement the provider registry and expose status, version, privacy, supported types, and diagnostics to one Plugins & Engines settings destination. Document conversion, downloads, and compression become explicit jobs. External executables run outside the main UI through the XPC helper using structured argument arrays and allowlisted paths.

The media-source registry keeps independent controllers and selects one active target rather than merging unrelated sessions. The display coordinator creates physical or virtual notch windows from shared state and prevents duplicated actions in all-display mode.

The MarkItDown runtime is generated reproducibly but excluded from Git. yt-dlp, FFmpeg, and ImageOptim are separately installed companions. The optional browser bridge is architectural documentation only and is not shipped.
