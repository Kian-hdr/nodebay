# Nodebay Browser Media Bridge

This optional first-party Chrome extension exposes media state from YouTube and YouTube Music tabs to Nodebay. From its popup, you can also grant access to other HTTP and HTTPS sites. Communication uses Chrome native messaging and a loopback-only connection from the bundled native host to the running Nodebay app.

The bridge does not request browsing-history, cookie, web-request, or clipboard permissions. Access to other sites is optional and requires an explicit Chrome permission prompt. It sends Nodebay a Chrome tab identifier, the visible media title and artist, playback state, time, duration, volume, and supported controls. Only YouTube tab URLs are forwarded for Nodebay's download action. It does not send this data to any server.

Equalizer capture is separate from media discovery. On macOS 14.2 or later, Nodebay uses a local Core Audio process tap to equalize Chrome audio, so the extension does not need to capture the tab. The extension's explicit **Enable EQ for This Tab** Web Audio path remains a compatibility fallback and is disabled automatically when Nodebay's native process equalizer takes over. Stopping or bypassing the native equalizer restores Chrome's ordinary audio path.

The unpacked extension has the stable ID `moppfhahpgimiknnknkmchmjljfhhdaf`. Nodebay installs a native-host manifest that accepts only that extension ID.

## Setup

1. Build and launch Nodebay.
2. In Nodebay's Media settings, select **Install Native Host**.
3. Select **Show Extension in Finder**.
4. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the revealed `extension` folder.
5. Confirm that Media settings shows **Connected**. YouTube and YouTube Music tabs with playable media appear independently in the Now Playing source selector.
6. To control videos or audio on other sites, open the extension popup and select **Enable Media on Other Sites**, then approve Chrome's permission prompt. Existing open tabs are checked automatically. Each tab with a playable HTML5 media element appears in Nodebay and can be selected for play or pause. Chrome's extension settings can revoke site access at any time.
7. On macOS 14.2 or later, select the Chrome source in Nodebay and choose an equalizer preset. The optional extension action is only a compatibility fallback for explicit per-tab YouTube capture.

Chrome requires this explicit extension installation. Nodebay does not install or enable it silently. Removing or disabling the extension disconnects the bridge and Nodebay falls back to the configured system media source. Sites using DRM, cross-origin embedded players, or media without an accessible HTML5 audio/video element may remain under System Now Playing.
