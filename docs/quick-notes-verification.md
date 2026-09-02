# Quick Notes: verification and release gate

Checked 2026-09-02 on Apple Silicon. This is local, unpublished work on
`fix/automatic-media-detection`, based on
`c732fa02c63eb065d59468b837835ae21eca352b`. Existing automatic-download changes
and unrelated proposal drafts were preserved. No new dependency was added.

## Implementation

- Explicit paste snapshots route file URLs to the file workflow, URL-only text
  to the downloader, and other text to persistent Markdown notes.
- The local actor preserves Markdown and Unicode, conservatively converts rich
  representations with plain-text fallback, and limits text to 1 MiB.
- Synchronized private temporary files are promoted atomically without replacing
  existing destinations. Notes use regular file bookmarks, not file promises.
- The shelf has a native New Note editor, selection/scroll-to-result, and
  three-second dismissible feedback. Settings exposes preferences and redacted
  diagnostics. No clipboard monitor, AI service or network client was added.
- Timestamp names are the default. Optional heading names intentionally accept
  only generic headings, since arbitrary short headings can contain secrets.

## Automated checks

| Check | Status | Evidence and limits |
|---|---|---|
| Complete automated suite | Passed | Final run: 129 tests in 18.432 seconds, including final malformed-rich-text hardening |
| Executable Swift content/storage/routing fixtures | Passed | Exact Markdown/plain UTF-8, Unicode, line endings, large text, mixed URLs, file URLs, collisions, fresh-actor persistence, bookmarks, private modes, injected partial-write cleanup, rich fallback and hostile list counters |
| Network-denied note creation | Passed | Swift service harness executed with `sandbox-exec` denying all network operations; this isolates note creation, not every existing app feature |
| Shelf/keyboard integration contracts | Included in suite | Source assertions cover normal text-field paste, unhandled event pass-through, open-window hit regions, regular file tiles, Quick Look, native drag, reference removal and Undo; not physical UI proof |
| Clean arm64 Debug | Passed | Separate clean DerivedData; signing disabled |
| Clean arm64 Release | Passed | Developer ID, hardened runtime, candidate build 22; arm64 verified with `file` |
| Candidate signing | Passed | Deep/strict codesign verification; Developer ID team HZWY8HT54D, stable bundle/team designated requirement, hardened runtime flag |
| License notices | Passed | `python3 scripts/generate_nodebay_notices.py --check` |
| Local documentation links / diff | Passed | `python3 scripts/verify_repository.py`; `git diff --check` |

## Physical UI checks

| Check | Status | Evidence and limits |
|---|---|---|
| Candidate launch | Passed | Temporary Developer-ID-signed Release executable launched without replacing `/Applications/Nodebay.app` |
| New Note action visible | Passed | Native accessibility tree exposed New Quick Note next to Add media download link in the empty shelf |
| Actual hover Command-V | Not verified | Tool-driven attempt created no file; read-only pointer/window inspection showed pointer outside the open-notch region. Physical test requested; no success inferred |
| Built-in display paste | Not run | Requires actual hover and paste, then file/shelf verification |
| External display paste | Not run | Sidecar was detected with negative screen coordinates; availability is not a successful paste test |
| Wired external monitor | Unavailable | No wired monitor present during this check |
| Editor paste, Space/Quick Look, rename, stacks | Not run | Existing normal-file paths reused; requires candidate UI exercise |
| Finder and another-app drag, reference removal, Undo | Not run | Automated file/bookmark and wiring checks do not prove destination-app acceptance |
| Light/dark, VoiceOver, keyboard focus, responsiveness | Not run | Semantic native controls implemented; visual/accessibility audit remains required |

## Release status

No commit, push, tag, GitHub release or Homebrew change was made. The public
1.0.0 release and installed application were not replaced. The test candidate
is not notarized and is not an approved distribution artifact.

The final signed candidate is running temporarily from
`/private/tmp/nodebay-quick-notes.Ea82Nd/FinalRelease/Build/Products/Release/Nodebay.app`
for physical verification. It has not replaced the installed application. The
four temporary build app registrations were removed from Launch Services;
`/Applications/Nodebay.app` is the sole registered top-level Nodebay application.
Quit the candidate and reopen `/Applications/Nodebay.app` to return to the
installed release. No shelf or preference restoration should overwrite changes
the user makes during testing.

Disposable local evidence is under `/tmp/nodebay-quick-notes.Ea82Nd/`:
`tests-final.log`, `debug-final.log`, `release-final.log`, and the compiled
`quick-note-tests` harness. Do not commit generated apps, runtimes or logs.

Before publication: complete physical paste and destination-app tests, resolve
any failures, choose a new version, create a signed/notarized artifact and
checksum, and present the complete release proposal for explicit approval.
