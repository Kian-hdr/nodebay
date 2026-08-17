# Homebrew

The proposed public tap is `Kian-hdr/homebrew-nodebay`. Its cask installs only `Nodebay.app` from the matching signed Apple Silicon GitHub release.

```bash
brew tap Kian-hdr/nodebay
brew install --cask nodebay
brew uninstall --cask nodebay
brew untap Kian-hdr/nodebay
```

The fully qualified install is `brew install --cask Kian-hdr/nodebay/nodebay`. The cask requires Apple Silicon and macOS 15 or later. The release URL, version, and SHA-256 must be updated together by the release packaging script. Homebrew's normal quarantine behavior remains enabled.

`zap` is optional and removes Nodebay preferences and caches only when the user explicitly requests it. It does not remove shelf source files, downloads, converted documents, or compressed images.
