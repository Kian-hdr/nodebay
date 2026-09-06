# Nodebay Browser Media Bridge

This optional first-party Chrome extension exposes only media state from explicitly permitted `youtube.com` and `music.youtube.com` tabs to Nodebay. Communication uses Chrome native messaging and a loopback-only connection from the bundled native host to the running Nodebay app.

The bridge does not request browsing-history, cookie, web-request, clipboard, or all-sites permissions. It sends Nodebay a Chrome tab identifier, the visible media title and artist, playback state, time, duration, volume, and supported controls. It does not send this data to any server.

Equalizer capture is separate from media discovery. On macOS 14.2 or later, Nodebay uses a local Core Audio process tap to equalize Chrome audio, so the extension does not need to capture the tab. The extension's explicit **Enable EQ for This Tab** Web Audio path remains a compatibility fallback and is disabled automatically when Nodebay's native process equalizer takes over. Stopping or bypassing the native equalizer restores Chrome's ordinary audio path.

The unpacked extension has the stable ID `moppfhahpgimiknnknkmchmjljfhhdaf`. Nodebay installs a native-host manifest that accepts only that extension ID.

## Setup

1. Build and launch Nodebay.
2. In Nodebay's Media settings, select **Install Native Host**.
3. Select **Show Extension in Finder**.
4. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the revealed `extension` folder.
5. Confirm that Media settings shows **Connected**. Compatible YouTube and YouTube Music tabs then appear independently in the Now Playing source selector.
6. On macOS 14.2 or later, select the Chrome source in Nodebay and choose an equalizer preset. The optional extension action is only a compatibility fallback for explicit per-tab capture.

Chrome requires this explicit extension installation. Nodebay does not install or enable it silently. Removing or disabling the extension disconnects the bridge and Nodebay falls back to the configured system media source.
