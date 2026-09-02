# STL Repair verification

Local unpublished work, 2026-09-02/03, branch `fix/automatic-media-detection`,
base `c732fa02c63eb065d59468b837835ae21eca352b`. Quick Notes and automatic-download
changes are preserved. No release or installed app was replaced.

## Evidence matrix

| Layer | Result | Evidence / limitations |
|---|---|---|
| Structural mesh validation | Passed, bounded fixtures | Binary/ASCII tetrahedron, boundary filling, exact duplicates/degenerates, inconsistent winding, disconnected components, header recovery, malformed/truncated/huge counts; output bounds and triangle readability |
| Engine and service tests | Passed | 13 test cases with real Blender runs behind OS network denial; actual Swift storage service and batch coordinator, mocked XPC/shelf boundaries |
| Batch | Passed in compiled harness | Mixed valid, invalid and unsupported files; partial result stack beside unchanged source; result persists when its mock reference is removed |
| Cancellation/crash/timeout | Passed at service boundary | Simulated failures and cancellation clean staging and preserve original; actual hung/killed engine stress not yet exercised |
| Full automated suite | Passed | Final run: 143 tests in 34.131 seconds, including notice enforcement, redacted shelf-log contracts and helper cancellation contracts |
| Clean arm64 Debug / Release | Passed | Final clean builds after helper hardening and shelf-log redaction; signed candidate build 23 uses unchanged marketing version 1.0.0 and is not a release |
| Actual app → XPC → Blender | Passed | Clicked Test Local Repair in signed candidate; native UI displayed “Passed; open boundary correctly reported” |
| Slicer import | Passed | Repaired synthetic open tetrahedron imported through native file dialogs in Bambu Studio 02.07.01.62 and OrcaSlicer 2.4.2. Both displayed 10×10×10 mm, 4 triangles, volume 166.667 mm³ |
| Slicer independence | Limited | Two separately installed applications, but Bambu/Orca share code ancestry; this is not two unrelated geometry-validation implementations |
| Visual comparison | Partial | Both slicer viewports displayed the small test object; no detailed original/result overlay or complex-model comparison completed |
| Shelf action, Finder/slicer dragging, relaunch and Undo | Not run physically | Normal file/bookmark paths reused; compiled tests are not proof of drag acceptance or live shelf persistence |
| Settings native UI | Passed in dark mode | Provider and 3D Models settings visible, Safe Repair default, automatic repair off, local-only status, test action |
| Light mode / VoiceOver / external display | Not run | Requires separate live verification |
| Physical print testing | Not run | No print was started; no physical correctness or printability claimed |
| Licensing and notice check | Passed | Blender companion recorded with full upstream license and source; governing GPL-3.0 unchanged; no engine bundled |
| Signing / architecture | Passed | Deep strict signature validation, Developer ID team HZWY8HT54D, hardened runtime, stable designated requirement; executable is arm64 |
| Native design advisory scan | Completed, not a UI pass | Tool only supports macOS 26/27 audit profiles; run with 26 without changing Nodebay's macOS 15 deployment floor. Existing custom-window/mouse handling findings remain review items |
| Notarization / publication | Not run | Explicit final approval and remaining verification required |

Disposable evidence: `/tmp/nodebay-stl.n8jqUs/`, including `stl-tests.log`,
`all-tests-final.log`, `debug-final.log`, `release-final.log`, `release-inventory.json`
and synthetic `fixtures/input.stl`, `output.stl`, `report.json`. Never commit
generated builds or proprietary models.

## Remaining release gates

Exercise the actual shelf
action and output drag in Finder and a slicer, test cancellation while an actual
engine is running, and inspect light/dark/accessibility behavior. No online API
or upload path exists; upload-consent and retention tests are not applicable.

The repair is intentionally conservative: no self-intersection detection or
repair, no remeshing, no component deletion, bounded input support and an exact
Blender version requirement. Slicer import does not establish printability.
Present final sources, notices, candidate artifact/checksum, limitations and
test results for approval before any public release or Homebrew change.

## Private candidate artifact

`/tmp/nodebay-stl.n8jqUs/Nodebay-STL-preview-build23-arm64-final.zip`

SHA-256: `338acf4979b428ffbc0dd4dce21476612553f640c50e002fa0edca8e505d512c`

Signed, not notarized, not release-ready. The candidate contains this worktree's
unpublished automatic-download and Quick Notes changes as well as STL Repair.
The final helper cancellation hardening and removal of path-bearing legacy
bookmark/drag logs were rebuilt and tested automatically;
the preceding signed candidate supplied the live Settings → XPC test evidence.
This is not a claim of a full final-binary live regression pass.

The installed `/Applications/Nodebay.app` was restored after testing. Temporary
STL app registrations were removed from Launch Services; no app files or user
models were deleted. The two synthetic slicer projects were closed without
saving. Physical printing, cloud upload and release publication were not performed.
