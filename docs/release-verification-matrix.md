# Release verification matrix

Checked on 2026-08-17 on Apple Silicon, macOS 26.6.1, and Xcode 26.6. `Passed` means the named command, fixture, artifact inspection, or live check completed successfully. Contract-test coverage is identified separately from end-to-end UI coverage.

| Check | Status | Evidence or limitation |
|---|---|---|
| Clean Debug build | Passed | Clean arm64 `xcodebuild`, unsigned Debug validation |
| Clean Apple Silicon Release build | Passed | Developer ID Release build succeeded |
| Code signing | Passed | Deep strict verification; Developer ID team `HZWY8HT54D`; hardened runtime; no debug entitlement |
| Notarization | Passed | Apple accepted submission `d75f3e51-238c-4e83-973f-cdfffcd16881` |
| Gatekeeper and stapling | Passed | Ticket stapled and validated; `spctl` reports `Notarized Developer ID` |
| One installed Nodebay application | Passed | Only `/Applications/Nodebay.app`; no Boring Notch app bundle |
| Launch at login | Not run | UI integration exists; restart behavior was not exercised in this pass |
| Accessibility permission detection | Passed | Final notarized app reports `Authorized for this signed app` after replacement and relaunch |
| Event-tap recovery and persistence | Passed | Final notarized app reports `Active`; authorization survived the update under the stable designated requirement |
| Volume and brightness HUD | Passed by user demonstration | User confirmed physical volume and brightness keys work; the automated harness cannot press hardware media keys |
| PDF conversion | Passed | Real generated fixture through bundled runtime |
| DOCX conversion | Passed | Real generated fixture through bundled runtime |
| Generated Markdown dragging | Unavailable end to end | Regular-file and file-promise contracts pass; Finder drag not rerun |
| File removal without source deletion | Passed contract | Removal, Undo, timer, dismiss, and no-delete contracts pass; UI flow not rerun |
| Image compression source safety | Passed | ImageOptim 1.9.3 safe-copy fixture; source SHA-256 unchanged |
| Completed download in shelf | Passed contract | Shelf insertion contract passes; direct local yt-dlp fixture also passes |
| Quick Look with Space | Passed contract | First-responder and Space handling tests pass; UI flow not rerun |
| Context-menu stability | Not run | No final interactive regression pass |
| File stacks and multi-file drag | Not run | Implementation exists; final Finder and persistence pass unavailable |
| External-display behavior | Passed for routing contract; physical provider test not rerun | All display modes have regression coverage. External brightness still depends on a compatible macOS, BetterDisplay, or Lunar provider |
| Runtime dependency integrity | Passed | Locked runtime rebuilt; PDF/DOCX; arm64; notices; XPC allowlist |
| No unintended Nodebay cloud traffic | Passed static and local guard | No analytics/update feed; MarkItDown sockets denied; packet capture not run |
| License-notice validation | Passed | Swift lock and processing integrations covered; generated notice checksum passes |
| Documentation links | Passed local | Thirty required files and all local Markdown links validated offline |
| Browser bridge contracts | Passed | Four permission, identity, command-allowlist, and Chrome native-framing tests |
| Multiple live Chrome tabs | Not run | Requires explicit installation of the unpacked extension and live YouTube fixtures |
| Homebrew cask syntax/style | Passed | Ruby syntax and `brew style` pass with version 0.1.1 and the final notarized checksum |
| Homebrew audit/install/uninstall | Unavailable | Requires the approved public release URL and tap |
| UI screenshots | Passed for checked dark-mode views | Nine privacy-safe repository screenshots; the unified Plugins & Engines page was recaptured from the installed app on 2026-08-17; light mode and final notarized build pending |
| Accessibility audit | Not run | VoiceOver, focus, hit-target, and reduced-motion manual pass pending |
| Large-batch memory/crash test | Not run | Requires dedicated stress fixtures and Instruments pass |

The final signed, notarized, stapled Nodebay 0.1.1 archive has SHA-256 `c497711aebcc549666f5f607e1c6c789d70c28d2636352ed918409f7197fb2a7`. It contains only `Nodebay.app` and passes Gatekeeper, staple, nested-code, hardened-runtime, timestamp, version, architecture, and bundled-notice verification.
