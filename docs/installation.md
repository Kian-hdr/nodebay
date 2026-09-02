# Installation

Nodebay currently requires Apple Silicon and macOS 15 Sequoia or later.

## Homebrew

```bash
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
```

After the one-time trust step, the fully qualified install is:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

## Manual installation

1. Download `Nodebay-<version>-arm64.dmg` from the [Nodebay releases page](https://github.com/Kian-hdr/nodebay/releases).
2. Verify its published SHA-256 checksum.
3. Open the disk image and drag `Nodebay.app` onto its Applications shortcut.
4. Launch Nodebay and grant only the permissions required by features you use.

Do not install artifacts from an old Boring Notch MarkItDown release as Nodebay.
