# Privacy and security

Nodebay has no account, analytics service, proxy, download server, or Nodebay cloud endpoint. Shelf state, bookmarks, stacks, conversions, compression jobs, and bounded diagnostics remain on the Mac.

MarkItDown and ImageOptim processing is local. yt-dlp contacts the user-provided source directly and therefore requires network access. Lyrics and source-provided artwork can also use the network. Browser-cookie import is disabled by default.

The optional Browser Media Bridge runs locally. Its Chrome extension is limited to `www.youtube.com` and `music.youtube.com`; it sends Nodebay only a tab identifier, visible media title and artist, playback timing/state, volume, supported-control flags, and whether that tab's equalizer capture is enabled. Chrome native messaging hands this to a bundled host, which connects only to Nodebay's loopback listener. Nodebay does not operate a relay, analytics service, or media-metadata server. Equalizer audio remains inside Chrome's local Web Audio graph and is never sent to Nodebay or a server. Audio capture requires a separate **Enable EQ for This Tab** action for each tab and is stopped on bypass, source change, tab close, or bridge disconnect.

The Plugins & Engines setup interface uses only an already-installed Homebrew executable and exact allowlisted packages. It does not invoke a shell, accept custom arguments, install Homebrew, read an administrator password, or bypass macOS authorization. ImageOptim and Blender require an explanatory confirmation because they are separate companion applications with larger downloads.

External tools run through structured `Process` arguments in an XPC helper with an executable allowlist, bounded logs, timeouts, and cancellation. User input is never interpolated into a shell command. Generated output paths are collision-safe and checked against traversal. Original shelf files are never deleted or modified by removal, conversion, or compression.

See [PRIVACY.md](../PRIVACY.md) and [SECURITY.md](../SECURITY.md).
