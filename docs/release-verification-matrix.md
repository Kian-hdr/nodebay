# Nodebay release verification

## Nodebay 1.1.0 (24): release checks, 2026-09-03

Application source built from clean detached commit `61b508b`. Subsequent
release commits update documentation, screenshots, workflow validation, cask
metadata and test assertions only; the compiled application source is unchanged.

| Check | Status | Evidence / boundary |
|---|---|---|
| Complete automated suite | Passed | 146 tests, final run 25.155 seconds; includes executable Swift fixtures |
| Clean Apple Silicon Debug / Release | Passed | Xcode 26.6, macOS 26.6.2; Release in a clean isolated checkout |
| PDF / DOCX / source preservation | Passed | Fresh pinned MarkItDown runtime and real generated fixtures; local-only guard and notices passed |
| MP4 / MP3 downloads | Passed | Local fixture server, real yt-dlp and FFmpeg; both results fully decoded; not a live YouTube service test |
| ImageOptim copy-first processing | Passed | 2,096,587-byte source unchanged; valid optimized copy 1,517,427 bytes |
| Production signing | Passed | Developer ID team HZWY8HT54D, all nested Mach-O signatures/timestamps, hardened runtime, no debug entitlement; private-build signing failure repaired |
| Authorization continuity | Passed diagnostic | Exact designated requirement matches installed 1.0.0; signed candidate reports Authorized and event tap Active without another prompt; no hardware key or restart claim |
| Quick Look extension packaging | Passed | Embedded, arm64, matching 1.1.0 (24), sandboxed read-only file access, no network entitlement; approved transparent renderer unchanged |
| App notarization | Passed | Submission `b403033c-0f65-470c-a5ab-5a6edf315b98` Accepted; app stapled and Gatekeeper accepted |
| DMG notarization | Passed | Submission `37a6d196-6ec2-47af-b00a-84d617803ea0` Accepted; DMG stapled and Gatekeeper accepted |
| Final artifacts | Passed | ZIP contains only Nodebay.app; DMG integrity verified and mounted read-only; visible payload Nodebay.app and Applications shortcut; enclosed app signature/staple passed |
| Candidate launch / About | Passed | Extracted notarized candidate launched; About shows 1.1.0 (24), Apple Silicon and creator; current screenshot retained |
| Settings conversion / STL repair | Passed interactive | Candidate's actual local conversion test Passed; XPC-to-Blender test Passed and correctly reported an open boundary |
| Quick Notes Settings | Passed inspection | Enabled state, privacy controls and storage visible; this is not a new physical Command-V test |
| About HTTP links | Passed | Source, releases, issues, license, acknowledgements, notices, privacy, security and Boring Notch upstream returned HTTP 200 |
| Notices / repository / cask style | Passed | Offline notice checksum, local documentation links, tracked-artifact exclusion and Homebrew style checks |
| Public artifacts | Passed | Re-downloaded both public DMG and ZIP; both match the published checksum file and cask. Release `nodebay-v1.1.0` is public, stable and latest |
| Homebrew upgrade | Passed | Actual `1.0.0 -> 1.1.0` upgrade on this Mac; installed 1.1.0 (24), signature/Gatekeeper/staple validation and launch passed |
| Data preservation | Passed sampled local state | All six existing files in managed Application Support and the captured preference files matched pre-upgrade hashes before relaunch; managed data also matched after reinstall. Private backups retained outside Git |
| Homebrew fresh receipt install | Passed | Non-zap uninstall followed by `brew install --cask Kian-hdr/nodebay/nodebay`; short `brew install --cask nodebay` correctly reports already current. Same account, not a fresh macOS account |
| Homebrew online audit | Passed | `brew audit --cask --strict --online Kian-hdr/nodebay/nodebay` completed successfully |
| Installed Finder preview | Passed interactive | Public Homebrew app rendered both `.md` and `.markdown` with main Nodebay quit; extension process ran from Applications; Escape dismissed the preview |
| App registrations | Passed | Only `/Applications/Nodebay.app` and its embedded preview remain registered as Nodebay; removed temporary/Trash registration records only, not files |
| GitHub CI | Running at publication readback | Independent run `33692504735`; local clean build and tests passed. Its result must not be inferred from local success |
| Remaining UI/hardware checks | Not rerun | Full VoiceOver, all supported OS versions, media-key presses, wake/clamshell, multi-monitor matrix, live YouTube and complete hover-paste/destination-app drag matrix |

Privacy-safe current screenshots: [About](screenshots/nodebay-about-1.1.0-dark.png),
[Quick Notes](screenshots/nodebay-quick-notes-1.1.0-dark.png),
[STL repair test](screenshots/nodebay-stl-repair-1.1.0-dark.png).
[Homebrew-installed Finder preview](screenshots/markdown-preview/markdown-homebrew-1.1.0-dark.png).
Earlier feature-specific reports below are historical evidence, not the current
installed/published version. No physical print qualification is claimed.

Final SHA-256:

```text
fa32abc9e161c936d5f08837cf284ac32e2f919cc478343411a151b9d90b9f4a  Nodebay-1.1.0-arm64.dmg
67b164501b724dd2e36fcb8f38815edab159bbed82e8dc102da7c5de46143ff0  Nodebay-1.1.0-arm64.zip
```

## Publication audit: 2026-09-03

The existing `nodebay-v1.0.0` release was published on 2026-09-02. It must not
be overwritten with the automatic-download, Quick Notes, STL Repair
and Markdown preview additions. The owner approved version 1.1.0, build 24.
No publication or replacement was performed during this audit.

| Check | Status | Evidence / boundary |
|---|---|---|
| Existing public 1.0.0 download | Passed | Downloaded the GitHub DMG again; SHA-256 matches the public cask and the historical checksum below |
| Existing public artifact integrity | Passed | `hdiutil verify`, `stapler validate` and Gatekeeper open assessment; Notarized Developer ID |
| Current automated suite | Passed | 146 tests, 28.110 seconds |
| Notices and repository checks | Passed | Offline notice validation, 30 required documentation files, local links, tracked-artifact exclusion and `git diff --check` |
| Packaging hardening | Implemented; final packaging not run | Explicit inside-out `.appex` signing; preview version, architecture and read-only/no-network sandbox checks |
| Previous private build 23 release audit | Failed | Nested `Contents/Resources/MediaRemoteAdapterTestClient` has the wrong signing team. The private build must not be distributed; rebuild using the production script that re-signs all nested Mach-O files |
| New release builds and notarization | Not run | Version decision and a final committed source snapshot required |
| New release Homebrew install/upgrade | Not run | No new release or tap update has been published |
| Physical and interactive regressions | Not rerun | See feature-specific verification documents; automated tests do not establish hover-paste, physical displays or destination-app dragging |

The local README now distinguishes published functionality from development
features and historical screenshots. The local cask no longer removes the
whole Nodebay Application Support directory during `--zap`; the public cask has
not yet received that safety change. Existing preferences and files were not
removed during this audit.

## Historical Nodebay 1.0.0 release verification matrix

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
