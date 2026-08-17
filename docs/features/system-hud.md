# System HUD replacement

When enabled, Nodebay replaces supported macOS volume and brightness overlays with its notch HUD. Accessibility is optional and is requested only for this feature. Authorization is checked by the signed main Nodebay process, and media-key interception starts only after macOS reports access granted.

Disabling the setting stops interception and restores normal system behavior. If authorization is revoked or an event tap fails, Nodebay keeps running and presents an actionable status instead of crashing or dismissing the notch.
