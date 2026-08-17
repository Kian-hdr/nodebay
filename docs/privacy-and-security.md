# Privacy and security

Nodebay has no account, analytics service, proxy, download server, or Nodebay cloud endpoint. Shelf state, bookmarks, stacks, conversions, compression jobs, and bounded diagnostics remain on the Mac.

MarkItDown and ImageOptim processing is local. yt-dlp contacts the user-provided source directly and therefore requires network access. Lyrics and source-provided artwork can also use the network. Browser-cookie import is disabled by default. The browser bridge is not shipped.

External tools run through structured `Process` arguments in an XPC helper with an executable allowlist, bounded logs, timeouts, and cancellation. User input is never interpolated into a shell command. Generated output paths are collision-safe and checked against traversal. Original shelf files are never deleted or modified by removal, conversion, or compression.

See [PRIVACY.md](../PRIVACY.md) and [SECURITY.md](../SECURITY.md).
