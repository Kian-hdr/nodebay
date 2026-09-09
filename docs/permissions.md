# Permissions

Nodebay requests permissions only when a selected feature requires them.

| Permission | Used for | Required |
|---|---|---|
| Accessibility | Intercepting media keys for the optional system HUD replacement | Only for HUD replacement |
| Files and folders | Persistent shelf bookmarks and user-selected output folders | For those files or folders |
| Apple Events | Controlling Apple Music or Spotify when installed and selected | Optional |
| Calendar and reminders | Calendar features | Optional |
| Camera | Mirror and camera features | Optional |
| Microphone | Optional audio visualization | Optional |
| System Audio Recording | Equalizing Spotify, QuickTime and identified Chrome audio; system audio visualization | Required for external-app EQ, separately on each Mac |
| Network client | Direct user-requested downloads, lyrics, and remote artwork | Feature-dependent |
| Chrome extension: native messaging | Local communication between explicitly installed Nodebay extension and app | Only for individual browser tabs |
| Chrome site access | Media state and controls on `www.youtube.com` and `music.youtube.com` | Limited to those two sites |
| Chrome tab capture | Apply the optional equalizer to one YouTube tab | Only after **Enable EQ for This Tab**; stops on bypass, source change, close, or disconnect |

Accessibility status is checked by the main Nodebay process, the process macOS authorizes. If macOS retains an obsolete permission entry, remove that entry, relaunch the signed `/Applications/Nodebay.app`, and add Nodebay again. The current migration-safe bundle identifier is documented in [migration-from-boring-notch.md](migration-from-boring-notch.md).

Media detection and equalization use different permissions. If a playing app is missing, open Nodebay Settings > Media, inspect its source status, and choose Refresh Sources. Apple Music, Spotify and QuickTime scripting can require System Settings > Privacy & Security > Automation. The Now Playing feed retries after helper failures and does not depend on a first-launch self-test passing.

For external EQ, play audio locally on this Mac, open Equalizer and enable it. Approve Nodebay in System Settings > Privacy & Security > Screen & System Audio Recording (called System Audio Recording on some macOS versions). A permission granted on the developer's Mac does not transfer with the download. After granting it, use Retry, or relaunch Nodebay if macOS asks. The panel reports active processing only after valid samples arrive. If permission or audio is unavailable, the source keeps its normal sound. Nodebay cannot process audio playing on a remote Spotify Connect device.

The browser bridge does not request Chrome's broad `tabs`, browsing-history, cookie, web-request, clipboard, or all-sites permissions. It must be loaded explicitly from Nodebay's bundled extension folder and can be disabled or removed from Chrome at any time.
