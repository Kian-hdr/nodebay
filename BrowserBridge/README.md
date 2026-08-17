# Nodebay Browser Media Bridge

This optional first-party Chrome extension exposes only media state from explicitly permitted `youtube.com` and `music.youtube.com` tabs to Nodebay. Communication uses Chrome native messaging and a loopback-only connection from the bundled native host to the running Nodebay app.

The bridge does not request browsing-history, cookie, tab-list, web-request, clipboard, or all-sites permissions. It sends Nodebay a Chrome tab identifier, the visible media title and artist, playback state, time, duration, volume, and supported controls. It does not send this data to any server.

The unpacked extension has the stable ID `moppfhahpgimiknnknkmchmjljfhhdaf`. Nodebay installs a native-host manifest that accepts only that extension ID.

## Setup

1. Build and launch Nodebay.
2. In Nodebay's Media settings, select **Install Native Host**.
3. Select **Show Extension in Finder**.
4. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the revealed `extension` folder.
5. Confirm that Media settings shows **Connected**. Compatible YouTube and YouTube Music tabs then appear independently in the Now Playing source selector.

Chrome requires this explicit extension installation. Nodebay does not install or enable it silently. Removing or disabling the extension disconnects the bridge and Nodebay falls back to the configured system media source.
