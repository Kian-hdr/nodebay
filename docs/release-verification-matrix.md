# Nodebay 1.0.0 release verification matrix

Checked on 2026-09-02 on Apple Silicon, macOS 26.6.2, and Xcode 26.6. `Passed` means the named command, fixture, artifact inspection, or live check completed successfully. Contract-test coverage is identified separately from end-to-end UI or physical-hardware coverage.

| Check | Status | Evidence or limitation |
|---|---|---|
| Automated test suite | Passed | 123 tests passed, including executable classification fixtures for YouTube Music, standard YouTube, structured music metadata, audio-only media, ambiguous content, and missing metadata |
| Clean Debug build | Passed | Clean arm64 Debug build completed during this release cycle |
| Clean Apple Silicon Release build | Passed | Developer ID Release build completed from commit `6f5102f` |
| Code signing | Passed | Deep strict verification; Developer ID team `HZWY8HT54D`; hardened runtime; secure timestamps; stable designated requirement |
| Notarization | Passed | Apple accepted the exact final DMG in submission `3cf0388f-b757-49f2-a7e2-657887e62aab` with no reported issues |
| Gatekeeper and stapling | Passed | DMG ticket stapled and validated; `spctl` reports `Notarized Developer ID` |
| Disk-image integrity and layout | Passed | `hdiutil verify` passed; visible payload is `Nodebay.app` plus the Applications shortcut |
| DMG installation and launch | Passed | Installed from the mounted DMG; `/Applications/Nodebay.app` launched as version 1.0.0 build 21 |
| One installed Nodebay application | Passed | Spotlight and filesystem checks found only `/Applications/Nodebay.app`; no installed Boring Notch app bundle |
| Launch at login | Not run | Integration exists; a full restart was not performed in this pass |
| Accessibility permission detection | Passed previously; not physically rerun on 1.0.0 | The stable signed requirement is preserved; current hardware-key interaction was not repeated after installing this candidate |
| Event-tap recovery and persistence | Passed by contracts; physical recovery not rerun | Recovery and safe pass-through contracts pass; wake and timeout recovery require manual hardware testing |
| Volume and brightness HUD | Passed previously by user demonstration; not rerun on 1.0.0 | The current candidate contains the same signed HUD implementation; automated tools cannot press physical media keys |
| PDF conversion | Passed | Bundled runtime converted a real PDF fixture locally and preserved the source |
| DOCX conversion | Passed | Bundled runtime converted a real DOCX fixture locally and preserved the source |
| Generated Markdown dragging | Passed by storage and drag contracts; manual Finder drag not rerun | Generated outputs are persistent regular files in Nodebay-managed storage |
| File removal without source deletion | Passed contract | Removal, Undo, timer, dismiss, and no-delete contracts pass |
| External-volume shelf access | Passed contract; physical SSD drop not rerun | Shelf items retain security-scoped access through bookmark creation |
| MP4 compression | Passed | Real FFmpeg fixture verifies a separate playable H.264/AAC result and unchanged source |
| Video-to-GIF conversion | Passed contract | Collision-safe persistent output, duration limit, no-overwrite arguments, and cleanup contracts pass |
| Image compression source safety | Passed | ImageOptim copy-first fixture completed; source SHA-256 remained unchanged |
| Local downloader | Passed | Local fixture server, yt-dlp inspection, download, output validation, and FFmpeg availability passed |
| Automatic media selection | Passed | Executable classifier fixtures and coordinator contracts cover Automatic, Always Video, Always Audio, Ask Every Time, one-time overrides, per-item playlist inspection, and refusal to start MP3 without FFmpeg |
| Live YouTube download | Passed previously by user demonstration; not rerun | Live site behavior can change and is not represented as a deterministic automated check |
| Completed downloads in shelf | Passed contract | Download promotion and shelf insertion contracts pass |
| Quick Look with Space | Passed contract | First-responder and Space handling tests pass; UI flow not rerun |
| Context-menu stability | Not run | No final interactive context-menu pass on the 1.0.0 candidate |
| File stacks and multi-file drag | Passed contract; manual Finder drag not rerun | Stack state and drag-provider contracts pass |
| External-display behavior | Passed routing contracts; physical display test not rerun | All display modes have regression coverage; external brightness depends on the monitor and available provider |
| Runtime dependency integrity | Passed | Locked MarkItDown runtime rebuilt; arm64 and notice checks passed |
| Local-first and network boundary | Passed static and local guards | MarkItDown sockets are denied; downloader connects directly to requested sources; packet capture was not run |
| License-notice validation | Passed | Generated third-party notice checksum is `aae59d5210db017ac2f787c8a3582ed412e75e3d2697ec3a15b2b8b29b1cb2e0` |
| Documentation links | Passed local | Thirty required files and all local Markdown links validated offline |
| Browser bridge contracts | Passed | Permission, identity, command allowlist, and native-framing tests pass |
| Multiple live Chrome tabs | Not run | Requires explicit bridge installation and live YouTube tabs |
| Homebrew cask syntax and style | Passed | Both repository cask copies parse successfully with Ruby; Homebrew reports no style offenses for the exact 1.0.0 cask |
| Homebrew online audit, install, and upgrade | Unavailable before publication | The final GitHub asset URL does not exist until approval and publication |
| UI screenshots | Historical | Existing privacy-safe screenshots remain accurate for the represented views; no complete 1.0.0 light/dark recapture was performed |
| Accessibility audit | Not run | VoiceOver, focus, hit-target, and reduced-motion manual pass remains pending |
| Large-batch memory and crash test | Not run | Requires dedicated stress fixtures and an Instruments pass |

The primary release artifact is `Nodebay-1.0.0-arm64.dmg`, size 86,731,065 bytes, SHA-256 `e33c60cbcf7aa2b80780b8f8c285e051fa94afe21f0b8db7cdaea9d8e0d4e772`. It is Developer ID signed, Apple-notarized, stapled, Gatekeeper accepted, disk-image verified, mounted, installed, and launched. The installed application reports Nodebay 1.0.0 build 21 and preserves the migration-safe bundle identifier `theboringteam.boringnotch` so existing preferences and permissions survive the update.
