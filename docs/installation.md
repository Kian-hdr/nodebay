# Installation

Nodebay currently requires Apple Silicon and macOS 15 Sequoia or later.

## Homebrew

After the first approved release is published:

```bash
brew tap Kian-hdr/nodebay
brew install --cask nodebay
```

Equivalent one-line form:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

## Manual installation

1. Download `Nodebay-<version>-arm64.zip` from the [Nodebay releases page](https://github.com/Kian-hdr/nodebay/releases).
2. Verify its published SHA-256 checksum.
3. Extract the archive and move the single `Nodebay.app` to `/Applications`.
4. Launch Nodebay and grant only the permissions required by features you use.

The public release and tap do not exist until the repository migration receives final approval. Do not install artifacts from an old Boring Notch MarkItDown release as Nodebay.
