# Nodebay privacy

Nodebay has no analytics service, advertising SDK, proxy, download server, or Nodebay cloud account. Shelf files, stacks, preferences, conversions, compression jobs, and processing logs stay on the Mac. Routine diagnostics retain bounded engine output and do not include converted document contents.

## Network activity

Network access occurs only when a feature inherently needs it:

- yt-dlp connects directly from the Mac to a media URL selected by the user. Browser-cookie access is disabled by default.
- Lyrics can query the public `lrclib.net` API when the user enables lyrics.
- Media artwork can be fetched from the artwork URL supplied by the selected playback source.
- Links opened by the user are handed to the default browser.

Microsoft MarkItDown conversion and ImageOptim compression are local-only. The MarkItDown XPC environment removes proxy variables and sets the bundled runtime to local-only mode.

The optional Browser Media Bridge is also local-only. Its explicitly installed Chrome extension can access media elements only on `www.youtube.com` and `music.youtube.com`. It sends Nodebay a tab identifier, visible media title and artist, playback state and timing, volume, and supported-control flags through Chrome native messaging and a loopback-only connection. It does not request browser history, cookies, broad tab-list access, web-request access, clipboard access, or access to other sites. Nodebay does not send this browser media data to a server.

## Files and permissions

Nodebay stores references and security-scoped bookmarks for shelf files and selected output folders. Removing a tile or dissolving a stack removes only Nodebay's reference. It does not delete the original file. Generated files use collision-safe names.

Calendar, camera, microphone, Accessibility, Apple Events, and folder access are requested only for features that need them. Each can be disabled in Nodebay or macOS Settings. Accessibility is needed only for system HUD replacement and related controls.

## Updates

Nodebay has no configured Sparkle update feed and never contacts the original Boring Notch appcast. Updates are available through GitHub and Homebrew. A future in-app update channel must be documented before activation.

Quick Notes reads copied content only after an explicit paste or New Note action, processes it locally, and retains only the resulting Markdown file. There is no continuous clipboard monitoring or content logging. Markdown Quick Look is sandboxed with no network entitlement and never loads remote resources. STL Repair passes a temporary copy to the separately installed Blender companion with network access denied; originals are never supplied for modification.
