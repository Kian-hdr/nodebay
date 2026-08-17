# Nodebay privacy

Nodebay has no analytics service, advertising SDK, proxy, download server, or Nodebay cloud account. Shelf files, stacks, preferences, conversions, compression jobs, and processing logs stay on the Mac. Routine diagnostics retain bounded engine output and do not include converted document contents.

## Network activity

Network access occurs only when a feature inherently needs it:

- yt-dlp connects directly from the Mac to a media URL selected by the user. Browser-cookie access is disabled by default.
- Lyrics can query the public `lrclib.net` API when the user enables lyrics.
- Media artwork can be fetched from the artwork URL supplied by the selected playback source.
- Links opened by the user are handed to the default browser.

Microsoft MarkItDown conversion and ImageOptim compression are local-only. The MarkItDown XPC environment removes proxy variables and sets the bundled runtime to local-only mode. Nodebay's optional browser bridge is not shipped in this source state, and individual browser-tab enumeration is therefore not claimed.

## Files and permissions

Nodebay stores references and security-scoped bookmarks for shelf files and selected output folders. Removing a tile or dissolving a stack removes only Nodebay's reference. It does not delete the original file. Generated files use collision-safe names.

Calendar, camera, microphone, Accessibility, Apple Events, and folder access are requested only for features that need them. Each can be disabled in Nodebay or macOS Settings. Accessibility is needed only for system HUD replacement and related controls.

## Updates

The unpublished Nodebay build has no configured update feed and never contacts the original Boring Notch appcast. A future signed update channel must be documented before release.
