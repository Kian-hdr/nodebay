# Nodebay 0.1.1 for Apple Silicon

Nodebay is the utility bay in your Mac's notch. Version 0.1.1 is the first public release and includes the production HUD reliability repair.

## HUD reliability

- Volume, mute, built-in display brightness, and supported keyboard-backlight keys are handled by a recoverable event tap.
- Accessibility is checked for the currently running signed Nodebay executable.
- Users upgrading from an ad-hoc build may need to remove the obsolete Nodebay Accessibility entry once, add `/Applications/Nodebay.app`, and enable it again.
- The event tap automatically recovers after timeout, wake, app activation, display changes, and notch-window recreation.
- Unsupported controls pass through to macOS, preserving normal hardware-key behavior.
- HUD presentation follows Built-in, Specific, Main, Follow Active, and All Displays placement modes.
- External monitor brightness requires a supported provider such as BetterDisplay or Lunar when macOS cannot control the monitor natively.
- Settings now reports authorization, event-tap, provider, display-routing, and last-error diagnostics without retaining key history.

## About Nodebay

All links now point to the canonical Nodebay source, releases, issue tracker, GPL-3.0 license, acknowledgements, third-party notices, privacy policy, security policy, and Boring Notch upstream.

## Installation and upgrade

```bash
brew tap Kian-hdr/nodebay
brew trust --cask Kian-hdr/nodebay/nodebay
brew install --cask nodebay
```

Homebrew 6 requires the one-time trust command for casks from third-party taps. After it is set, the fully qualified install is:

```bash
brew install --cask Kian-hdr/nodebay/nodebay
```

To upgrade an existing Homebrew installation:

```bash
brew update
brew upgrade --cask nodebay
```

The release ZIP contains only `Nodebay.app`. Nodebay preserves the legacy bundle identifier in version 0.x so existing preferences, shelf state, bookmarks, launch-at-login state, and compatible privacy authorization remain available.

## Privacy and attribution

Document conversion and image compression run locally. Media downloads connect directly from the Mac to the source selected by the user. Nodebay operates no proxy, analytics, or processing server.

Nodebay is GPL-3.0 software created by Kian Konrad Tajbakhsh and based on Boring Notch commit `44dd999f70493da48209c99e9f873c47f2e55c83`. Third-party projects do not endorse Nodebay.
