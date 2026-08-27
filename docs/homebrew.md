# Homebrew

The official public tap is `Kian-hdr/homebrew-nodebay`. Its cask installs only `Nodebay.app` from the matching signed, notarized Apple Silicon GitHub release.

```bash
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
brew uninstall --cask nodebay
brew untap Kian-hdr/nodebay
```

Homebrew 6 requires the one-time `brew trust` command for third-party casks. This command trusts only the Nodebay cask. After that, the fully qualified install is `brew install --cask Kian-hdr/nodebay/nodebay`. The cask requires Apple Silicon and macOS 15 or later and installs yt-dlp and FFmpeg as separate Homebrew formula dependencies. They are not bundled into or modified by Nodebay. The release URL, version, and SHA-256 must be updated together by the release packaging script. Homebrew's normal quarantine behavior remains enabled.

`zap` is optional and removes Nodebay preferences and caches only when the user explicitly requests it. It does not remove shelf source files, downloads, converted documents, or compressed images.
