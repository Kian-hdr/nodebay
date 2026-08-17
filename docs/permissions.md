# Permissions

Nodebay requests permissions only when a selected feature requires them.

| Permission | Used for | Required |
|---|---|---|
| Accessibility | Intercepting media keys for the optional system HUD replacement | Only for HUD replacement |
| Files and folders | Persistent shelf bookmarks and user-selected output folders | For those files or folders |
| Apple Events | Controlling Apple Music or Spotify when installed and selected | Optional |
| Calendar and reminders | Calendar features | Optional |
| Camera | Mirror and camera features | Optional |
| Microphone or system audio | Audio visualization features | Optional |
| Network client | Direct user-requested downloads, lyrics, and remote artwork | Feature-dependent |
| Chrome extension: native messaging | Local communication between explicitly installed Nodebay extension and app | Only for individual browser tabs |
| Chrome site access | Media state and controls on `www.youtube.com` and `music.youtube.com` | Only for individual browser tabs |

Accessibility status is checked by the main Nodebay process, the process macOS authorizes. If macOS retains an obsolete permission entry, remove that entry, relaunch the signed `/Applications/Nodebay.app`, and add Nodebay again. The current migration-safe bundle identifier is documented in [migration-from-boring-notch.md](migration-from-boring-notch.md).

The browser bridge does not request Chrome's broad `tabs`, browsing-history, cookie, web-request, clipboard, or all-sites permissions. It must be loaded explicitly from Nodebay's bundled extension folder and can be disabled or removed from Chrome at any time.
