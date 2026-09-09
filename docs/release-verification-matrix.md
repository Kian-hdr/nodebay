# Nodebay release verification

## Nodebay 1.2.1 (28): updater candidate, 2026-09-09

**Not published.** Build 28 adds signed in-app updates; build 26 below is superseded and its artifact checks do not establish build 28 acceptance. The original 640 × 190 notch dimensions remain fixed.

| Check | Status | Evidence / limit |
| --- | --- | --- |
| Nodebay signing key | Passed | Actual pinned Sparkle 2.9.5 and independent CryptoKit verification agree; both reject modified feed bytes. Private key stays outside source |
| Updater policy, privacy and branding | Passed | 20 focused tests, including compiled policy behavior for legacy choice, opt-out, configured feed and active-work gates |
| Shelf persistence and overlapping activity | Passed | Four ordering/recovery tests and two activity cases; native update continuity remains pending |
| Final source build and full suite | Pending | Integration in progress |
| Older build 27 to unchanged production build 28 | Pending | Separate testing feed; must exercise actual downloaded signed archive, install, relaunch and retained settings/data |
| Invalid signature / interrupted download | Pending | Real installed updater acceptance still required |
| Stable GitHub release, signed feed and Homebrew | Pending | No final artifact or cask publication yet |

## Nodebay 1.2.1 (26): superseded bugfix candidate checks, 2026-09-09

**UNPUBLISHED release candidate.** The clean Apple Silicon Release package was
built from source commit `2442410e4c3123f732b900e8f7dc8848788f1994` on
macOS 26.6.2 with Xcode 26.6. The app is signed, Apple-notarized and stapled;
final ZIP verification passed. DMG notarization, final installation and native
checks, GitHub publication and the Homebrew lifecycle remain pending.
The intended version is 1.2.1, build 26, with a new immutable tag and download
files. Existing 1.2.0 assets remain unchanged.

| Check | Status | Evidence / boundary |
|---|---|---|
| Clean Apple Silicon Release package | Passed | Built from clean source commit `2442410e4c3123f732b900e8f7dc8848788f1994`; application metadata is 1.2.1 (26). All 170 packaged Mach-O files contain arm64, require macOS 15.0 or earlier and have no external absolute library dependencies |
| Complete automated suite | Passed | All 222 tests passed in 53.636 seconds for the release source, including the native layout overlap regression |
| Media discovery and recovery | Passed focused tests | 22 media/recovery/selection/QuickTime/startup tests; production controller harness covers failed-helper restart, cleared issues, shutdown/deallocation, missing resources, fragmented UTF-8 and closing a silent pipe |
| Untitled active media | Passed bundled-framework regression | MediaRemoteAdapter v0.7.7, exact source `e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6`; binary metadata harness accepts an active client without a title and rejects missing client/playback keys. Application fixtures prevent borrowing metadata across clients. This does not establish playback in every chat app |
| Media adapter portability | Passed artifact inspection | Rebuilt framework and diagnostic helper contain arm64 slices with macOS 15.0 minimum and only system-library dependencies. Corresponding source, build instructions and BSD notice are retained in [SOURCE.md](../mediaremote-adapter/SOURCE.md) |
| Player layout | Passed native SwiftUI geometry regression | Six off-screen native layout cases at three widths, with and without lyrics, keep metadata, timeline and controls separate. The old layout fails the same overlap check. Installed candidate visually verified at the original 640 × 190 size; lyrics share the artist row. Final packaged display checks remain pending |
| Equalizer DSP and startup policy | Passed focused tests | 13 EQ tests plus six QuickTime tests. Production DSP processes a 1 kHz signal, applies a live 12 dB cut, handles four interleaved/separate buffer combinations, and keeps the unmuted probe output silent. Zero-filled, nonfinite and incompatible-channel fixtures fail safely |
| Spotify routing and recovery UI | Passed installed-candidate checks | Specific Spotify/helper matching and late source resolution; actual authenticated Spotify audio reached the active state only after valid nonzero capture. Live bass adjustment, bypass/re-enable and pause/resume recovery succeeded. Fresh permission grant/denial and output-device switching remain untested |
| Native Spotify playback | Passed installed-candidate checks | User signed in directly. Spotify source, track metadata, Play/Pause and advancing time verified. EQ displayed Processing audio locally; bass 0 → −6 dB → flat, bypass and resume verified. These are native routing/UI observations plus deterministic DSP tests, not physical speaker spectral measurements |
| PNG/image compression repair | Passed nine production-service tests | Read-only files/folders and symlinks produce independent writable copies in Nodebay storage; tests cover original preservation, collisions, cancellation, optimizer errors and invalid output. The optimizer boundary is stubbed; this is not a new live ImageOptim GUI test |
| Converter runtime portability | Passed binary checks and current-host execution | Replaced the Homebrew-built Python runtime whose binaries required macOS 26. The verified Python.org CPython 3.13.15 arm64 interpreter targets macOS 11; all 158 frozen runtime Mach-O files pass the macOS 15 maximum, arm64 and external-library checks. Actual execution on macOS 15 remains untested |
| Compatibility regression guard | Passed seven tests | Real compiled fixtures reject macOS 26-only, Intel-only and developer-local library dependencies; both modern and legacy deployment metadata are parsed. Runtime build, package assembly and final archive verification invoke the guard |
| Bundled conversion and runtime notices | Passed locally | Nine wrapper tests and real PDF/DOCX conversions; originals preserved and remote URL rejected. Official installer checksum, PSF Developer ID and Apple notarization verified before private extraction. Incorporated-library notices are included; dependency versions remain pinned |
| Release-source independent CI | Passed | [Apple Silicon build and verification](https://github.com/Kian-hdr/nodebay/actions/runs/34398399898) completed successfully at 20:08:30 UTC on 2026-09-09 for exact source `2442410e4c3123f732b900e8f7dc8848788f1994`; repository/notices, runtime, local downloader fixture and clean Release build passed |
| Final app signing, notarization and Gatekeeper | Passed | Developer ID team `HZWY8HT54D`; stable designated requirement, hardened runtime, nested signatures/timestamps and debug-entitlement exclusion passed. App submission `99d7bcb2-140a-46f5-9a10-003e35937b9d` Accepted; staple and Gatekeeper passed. Final main SHA-256 is recorded below |
| Final ZIP | Passed | Contains only Nodebay.app; all artifact-verifier checks passed, including binary compatibility, release metadata, notices, nested signatures, preview sandbox, Gatekeeper and staple. Final hash and size are recorded below |
| DMG construction and enclosed app | Passed pre-notarization checks | Signed DMG integrity passed. Read-only mount contains Nodebay.app and an Applications shortcut; enclosed main executable matches the final ZIP app and its signature/staple pass |
| DMG notarization and final installation | Pending | DMG submission reports the saved Keychain item unavailable after screen lock. Unlock and retry are pending; credentials have not been recreated. DMG acceptance/staple, final hash, Gatekeeper, installation and final packaged native media/EQ checks remain pending |
| GitHub and Homebrew | Pending | No 1.2.1 publication or cask lifecycle result is claimed. Verify hosted bytes, cask checksum/style/online audit, upgrade and non-zap reinstall, including data/settings preservation |

Release fields to complete from the final artifact and hosted state:

| Field | Current value |
|---|---|
| Application source commit | `2442410e4c3123f732b900e8f7dc8848788f1994` |
| Release tag and tag commit | Intended `nodebay-v1.2.1`; not created |
| Successful release-source CI URL | [Run 34398399898](https://github.com/Kian-hdr/nodebay/actions/runs/34398399898), successful for the exact source commit |
| Final packaged main executable SHA-256 | `3813dbb3d84c3fa783fc3ba265846e32512f41a1def0ba641c4074d62d1914df` |
| Final installed main executable SHA-256 | Pending installation from the final artifact |
| App notarization submission ID/status | `99d7bcb2-140a-46f5-9a10-003e35937b9d`, Accepted; app stapled and validated |
| DMG notarization submission ID/status | Pending Keychain access after unlock; no completed submission claimed |
| `Nodebay-1.2.1-arm64.dmg` SHA-256 and size | Pending final notarization and stapling |
| `Nodebay-1.2.1-arm64.zip` SHA-256 and size | `e1a429a6b59355f7365e826adfbdd0c95fd52d69f33b97b1ddeadf1531b3a034`; 87,408,640 bytes |
| Public release URL and anonymous download comparison | Pending |
| Homebrew tap commit and lifecycle results | Pending |
| Final native media/layout/EQ observations and host | Pending final packaged installation; earlier installed-candidate checks on macOS 26.6.2 remain distinct |

The Python compatibility finding corrects an earlier packaging assumption:
1.2.0 converted documents successfully on the developer's macOS 26 Mac, but its
bundled Python required macOS 26 despite the application's advertised macOS 15
minimum. Passing its earlier conversion tests did not establish macOS 15 runtime
compatibility. This candidate checks the actual minimum of every packaged binary.

Native media behavior on the recipient's Mac, fresh capture-permission grant/denial,
Bluetooth/AirPlay output changes and full
accessibility/display coverage remain separate from deterministic fixture results.
Process EQ applies to audio emitted on the Mac running Nodebay. It does not
process Spotify Connect playback on a remote device. See [Equalizer](features/equalizer.md)
and the [candidate release notes](release-notes-1.2.1.md).

## Nodebay 1.2.0 (25): release checks, 2026-09-06

Application source was built from clean commit `52e20970174c25fc60b4c90e49f476d98a542c37`.
The release tag adds documentation and cask metadata only; compiled application
source, dependency locks, runtime notices and privacy payload are unchanged.

| Check | Status | Evidence / boundary |
|---|---|---|
| Complete automated suite | Passed | All 198 tests passed in 55.990 seconds from the clean release checkout; also passed after both UI changes in the development checkout |
| Independent GitHub CI | Passed | [Apple Silicon build and verification](https://github.com/Kian-hdr/nodebay/actions/runs/34045131443), exact release-tag commit `a11e340`; tests, notices, runtime/conversion/downloader fixtures and clean Release build |
| Bubble sizing | Passed regression and native UI | Original code fails the new resize regression. Short, multiline, emoji, Arabic and long messages preserve natural sizing and the 78% cap. Native short and wrapped messages were inspected |
| API correctness | Passed mocked and native checks | Transport/coordinator tests cover budgets, invalid output, safe errors, cancellation and stale configuration. Real Validate Connection passed. The installed notarized app answered “Reply exactly OK.” with “OK” via OpenAI API/gpt-5-mini, without a Knowledge Folder or credential inspection |
| Key entry and About | Passed native final artifact | Visible API key heading, paste instructions, bordered secure field and saved-key status; About displays 1.2.0 (25), Apple Silicon and creator |
| Signed clean Release | Passed | Developer ID team HZWY8HT54D, stable designated requirement, hardened runtime, secure timestamps on nested code, no debug entitlement, arm64 app/runtime; final main SHA-256 `0bb3a302ebffd554801d66e03485acf3acf95c09e0338fa737e112a61f0e19ed` |
| Bundled conversion and notices | Passed | Pinned CPython/MarkItDown runtime; real PDF/DOCX conversions, source preservation and local-only guard; required licenses and corresponding-source pointer |
| App notarization | Accepted | Submission `d3497ea0-4af7-4d88-a17d-5011e48f96a7`; no issues, stapled app and Gatekeeper accepted |
| DMG notarization | Accepted | Submission `4fb0be16-c7f7-41cd-8f95-3df19f53ddea`; no issues, stapled DMG, signature, Gatekeeper and integrity checks passed |
| Final ZIP and DMG | Passed | ZIP contains only Nodebay.app. Read-only DMG visibly contains Nodebay.app and Applications shortcut; enclosed app matches ZIP and passes signature, ticket and Gatekeeper checks |
| Final DMG installation | Passed on this Mac | Installed from mounted DMG into /Applications, verified signature/staple/hash, launched and inspected native UI and real API reply; mount ejected |
| Data and settings continuity | Passed on this Mac | All 13 existing managed app files and four AI/companion preference values retained identical hashes; saved API key remained usable. No credential value read or replaced |
| Cask definition | Passed local checks | Version and final DMG checksum synchronized; Homebrew style and Ruby syntax pass; yt-dlp/FFmpeg remain separate dependencies |
| Public downloads | Passed | Stable GitHub release `nodebay-v1.2.0`; anonymous re-downloads of DMG, ZIP and checksum file match the original verified bytes |
| Homebrew lifecycle | Passed on this Mac | Strict online cask audit, targeted 1.1.0 → 1.2.0 upgrade, non-zap uninstall/reinstall, installed signature/Gatekeeper/staple, native launch and actual API reply passed. All 13 managed files and four AI/companion settings preserved; installed preview registration removed on uninstall. This is a same-account test, not a clean-account test |
| Longhaul companion | Passed bounded protocol and native checks | 44 client/view and 60 protocol/relay assertions; both control locations and reconnection verified with the separate companion. Separate companion popover and bounded OS assertion checks do not by themselves establish actual menu-bar icon visibility; that UI remains the companion's own verification responsibility. Longhaul remains unbundled; no physical closed-lid or overnight claim |

Final immutable artifacts:

```text
7acb9b1b966cafe38158d1044088e411d4703a25a38c6041016a5b7f6c719f12  Nodebay-1.2.0-arm64.dmg
63ea96e450115f843afe5ec59ad538b882caeb48ba72129bf69224614d6dade8  Nodebay-1.2.0-arm64.zip
```

The UI and installer checks ran on macOS 26.6.2. Other supported OS versions,
VoiceOver/Full Keyboard Access, multi-display and physical drag/audio matrices
were not fully rerun. Browser-tab runtime verification still requires an explicitly
configured bridge. Knowledge Folder retrieval was not part of the API test.
Quick Chat delivers complete replies; App Server/token streaming remain disabled.
Restricted CLI evidence is bounded and does not establish universal tool isolation
or provider-wide retention. See [Quick Chat](features/quick-chat.md).

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
| Quick Look extension packaging | Passed before latest visual adjustment | Embedded, arm64, matching 1.1.0 (24), sandboxed read-only file access, no network entitlement; refreshed visual verification is required for the new full-bleed semantic material |
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
| GitHub CI | Passed | Independent Apple Silicon run [33692504735](https://github.com/Kian-hdr/nodebay/actions/runs/33692504735) completed successfully: tests/notices, pinned runtime, local downloader, clean Release build and generated-artifact exclusion |
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
