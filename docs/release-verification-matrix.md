# Release verification matrix

Checked on 2026-08-17 on Apple Silicon, macOS 26.6.1, and Xcode 26.6. `Passed` means the named command, fixture, artifact inspection, or live check completed successfully. Contract-test coverage is identified separately from end-to-end UI coverage.

| Check | Status | Evidence or limitation |
|---|---|---|
| Clean Debug build | Passed | Clean arm64 `xcodebuild`, unsigned Debug validation |
| Clean Apple Silicon Release build | Passed | Developer ID Release build succeeded |
| Code signing | Passed | Deep strict verification; Developer ID team `HZWY8HT54D`; hardened runtime; no debug entitlement |
| Notarization readiness | Passed with pending external step | Artifact meets local prerequisites; Apple submission and staple not run |
| Gatekeeper acceptance | Failed as expected pre-notarization | `spctl` reports `Unnotarized Developer ID` |
| One installed Nodebay application | Passed | Only `/Applications/Nodebay.app`; no Boring Notch app bundle |
| Launch at login | Not run | UI integration exists; restart behavior was not exercised in this pass |
| Accessibility permission detection | Passed | Main process reported authorization granted |
| HUD functionality | Passed partially | Event tap started; automated hardware media-key visual output unavailable |
| PDF conversion | Passed | Real generated fixture through bundled runtime |
| DOCX conversion | Passed | Real generated fixture through bundled runtime |
| Generated Markdown dragging | Unavailable end to end | Regular-file and file-promise contracts pass; Finder drag not rerun |
| File removal without source deletion | Passed contract | Removal, Undo, timer, dismiss, and no-delete contracts pass; UI flow not rerun |
| Image compression source safety | Passed | ImageOptim 1.9.3 safe-copy fixture; source SHA-256 unchanged |
| Completed download in shelf | Passed contract | Shelf insertion contract passes; direct local yt-dlp fixture also passes |
| Quick Look with Space | Passed contract | First-responder and Space handling tests pass; UI flow not rerun |
| Context-menu stability | Not run | No final interactive regression pass |
| File stacks and multi-file drag | Not run | Implementation exists; final Finder and persistence pass unavailable |
| External-display behavior | Unavailable | No external display attached for this pass |
| Runtime dependency integrity | Passed | Locked runtime rebuilt; PDF/DOCX; arm64; notices; XPC allowlist |
| No unintended Nodebay cloud traffic | Passed static and local guard | No analytics/update feed; MarkItDown sockets denied; packet capture not run |
| License-notice validation | Passed | Swift lock and processing integrations covered; generated notice checksum passes |
| Documentation links | Passed local | Thirty required files and all local Markdown links validated offline |
| Homebrew cask syntax/style | Passed | Ruby syntax and `brew style` pass in the prepared local tap |
| Homebrew audit/install/uninstall | Unavailable | Requires the approved public release URL and tap |
| UI screenshots | Passed for checked dark-mode views | Nine privacy-safe repository screenshots; light mode and final notarized build pending |
| Accessibility audit | Not run | VoiceOver, focus, hit-target, and reduced-motion manual pass pending |
| Large-batch memory/crash test | Not run | Requires dedicated stress fixtures and Instruments pass |

The current pre-notarization artifact is `build/nodebay-homebrew-arm64-release/Nodebay-0.1.0-arm64.zip`, SHA-256 `b9deedc0cd4d2c111ac7d753cdb118f37a776f2ba301b76707d04a18a8c2e71a`. It must not be published as the final Homebrew asset until Apple notarization, stapling, re-zipping, and checksum replacement complete.
