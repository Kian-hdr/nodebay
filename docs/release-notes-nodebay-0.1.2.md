# Nodebay 0.1.2 for Apple Silicon

Nodebay 0.1.2 is a maintenance update for the Settings window and Homebrew installation documentation.

## Settings reliability

- The Settings window is no longer eligible for automatic macOS window restoration.
- A restored or system-ordered Settings window is hidden unless it was opened through an explicit Nodebay action.
- Intentional opening through the Nodebay menu, notch controls, context menu, onboarding, and `Command-,` remains available.

## Homebrew installation

Homebrew 6 requires a one-time trust step for casks from third-party taps:

```bash
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
```

After the trust step, the fully qualified installation command is:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

To upgrade an existing installation:

```bash
brew update
brew upgrade --cask nodebay
```

Nodebay retains its migration-safe bundle identifier, preferences, shelf state, bookmarks, and Accessibility authorization. The archive contains only `Nodebay.app`.
