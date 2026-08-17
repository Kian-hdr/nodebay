# Browser media bridge

- Purpose: opt-in enumeration and control of individual compatible browser media tabs
- Version: 0.1.0
- Status: first-party extension and native host bundled with Nodebay; extension installation remains explicit
- Browser: Google Chrome
- Behavior: Chrome native messaging plus a loopback-only connection to the running Nodebay app
- Inputs: media elements on `www.youtube.com` and `music.youtube.com`
- Outputs: independent local media sessions and an allowlisted set of playback controls
- Permissions: `nativeMessaging` plus host access only for the two supported YouTube origins
- Installation path: the extension and host are inside `Nodebay.app/Contents/Resources/BrowserBridge`; the generated Chrome host manifest is in the current user's `Library/Application Support/Google/Chrome/NativeMessagingHosts`
- Failure: stale sessions expire, a disconnected active tab falls back to the configured media source, and the UI remains available
- Diagnostics: native-host installation, extension connection, exact version, compatible-tab count, and bounded errors
- Source and license: first-party Nodebay code, GPL-3.0

The bridge does not request browser history, cookies, the broad `tabs` permission, web-request access, or all-site access. No media metadata is sent to a Nodebay server or third party. Chrome, Google, and YouTube do not endorse Nodebay.

Follow the exact setup steps in [`BrowserBridge/README.md`](../../BrowserBridge/README.md). Static permission and native-framing tests are automated; an unpacked Chrome extension still requires user confirmation for end-to-end browser verification.
