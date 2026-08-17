# Homebrew MarkItDown Edition

This is a fixed Apple Silicon distribution of Boring Notch 2.8-beta.0 with the
local MarkItDown shelf integration. It is based on the public upstream PR branch
and remains licensed under GPL-3.0.

## Install

```bash
brew install --cask Kian-hdr/boring-notch-markitdown/boring-notch-markitdown
```

The cask is restricted to Apple Silicon and macOS Sonoma or newer. It downloads
a versioned release archive and verifies its SHA-256 checksum before installing
`boringNotch.app` in `/Applications`.

The official `boring-notch` cask conflicts with this edition because both use
the same application name, bundle identifier, settings, and shelf data. Remove
an existing Homebrew-managed official edition before installing this one.

## Updates

The Sparkle update controls are disabled in this fixed build. An official update
could otherwise replace the app with a build that does not yet contain the
MarkItDown integration. Upgrade through this tap when a new MarkItDown edition
is published.

## Uninstall

```bash
brew uninstall --cask Kian-hdr/boring-notch-markitdown/boring-notch-markitdown
```

Uninstalling the cask does not delete Boring Notch preferences or shelf data.

## Source and licensing

The exact source is available from the release tag in
[`Kian-hdr/boring.notch`](https://github.com/Kian-hdr/boring.notch). Boring Notch
is GPL-3.0. Microsoft MarkItDown 0.1.7 is bundled unmodified under MIT. Complete
runtime notices are included in `THIRD_PARTY_LICENSES_MARKITDOWN` and inside the
application’s generated MarkItDown runtime.
