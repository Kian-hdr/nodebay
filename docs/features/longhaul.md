# Longhaul companion

Implemented locally. Control-location negotiation passed focused model, client,
relay and layout checks and bounded signed native routing checks on 2026-09-06.
Previous direct-toggle verification is recorded separately below. No public
Longhaul installer or release URL is configured.

Longhaul remains a standalone app and owns sleep protection, battery policy and
recovery. Nodebay can present its status and report supported processing work.
Installing either app does not pair them. Plugins & Engines contains a dedicated
Longhaul section with Not installed, Available, Connected and Needs attention
states. When a compatible unpaired service is available, Nodebay offers a
connection once through a quiet notch notice; Connect remains accessible in
settings. Connection approval is handled by Longhaul.

## Native interface

- When Longhaul selects Nodebay as its control location, the open notch has a
  fixed 28×28-point automatic-protection button. Choosing Longhaul's menu bar
  removes the entire button from its parent row, including the adjacent spacing.
  Settings connection controls and Open Longhaul remain reachable in either mode.
  The last accepted location is restored before the first connection refresh.
- A sun means
  automatic protection is enabled; a moon means it is paused. This reflects the
  acknowledged `snapshot.enabled` setting, not whether a job currently needs a
  power assertion. Job counts never alter its width.
- Clicking requests only Pause or Resume over the existing authenticated
  connection. Pending requests show an indicator and block repeated clicks until
  a newer snapshot from the same relay instance confirms the requested setting.
  No optimistic setting change or timed Keep Awake command is sent by the button.
- Unpaired and unavailable states use distinct disabled glyphs with explanatory
  help and accessibility values. Pending confirmation expires after 15 seconds
  when checked by the next poll. Failure and relay restart remain explicit and
  never automatically replay the mutation.
- The context menu provides the same automatic-protection action and a separate
  Open Longhaul command. There is no detail popover. Nodebay settings retain
  connection/setup and the notice preference; jobs, battery policy, recovery and
  detailed controls live in Longhaul's own window.
- Significant notices use a dedicated horizontal notch surface, at most one every
  30 seconds for six seconds. Ordinary progress does not open the drawer, select a
  tab, activate an app or change Spaces. The existing display placement policy is
  respected.
- The Longhaul notice setting is separate from volume, brightness and media HUD
  settings. A notice is acknowledged only after its view is presented. A bounded
  persistent ledger prevents duplicate presentation after reconnect/restart and
  retries lost acknowledgements. If the notch is hidden, busy or unavailable,
  Longhaul retains responsibility for fallback notification.

Standard grouped Form, LabeledContent, Toggle, Button, context menu and
ProgressView controls preserve the existing Nodebay deployment range. No new
macOS 26/27-only UI API is required. The short black notch notice is a justified
departure from a standard window because Nodebay's existing surface surrounds
the physical camera housing; its text has explicit accessible labels and a help
description. Settings and the context menu use semantic native appearance. Live
keyboard, VoiceOver, appearance and camera-safe-area checks remain required.

## Local protocol and authentication

Protocol version 1 uses a per-user NSXPC Mach service,
`space.exlumina.longhaul.companion`, with Objective-C protocol
`LonghaulCompanionProtocol` and one `exchange(_:with:)` Data method. The sandboxed
main app reaches it through Nodebay's existing unsandboxed processing helper.
No TCP/Unix socket, custom URL listener, shell, arbitrary executable or arbitrary
service selector is exposed by this integration.

Every hop checks this user's effective UID and a valid Developer ID signature
for the exact peer identifier and team `HZWY8HT54D`. The Nodebay helper sets an
incoming code-signing requirement before resuming each connection. The new API
also verifies its caller. Nodebay sets the helper requirement before resuming;
the helper does the same for Longhaul's relay. This intentionally rejects
unsigned/ad-hoc runtime clients. `script/build_and_run.sh` already uses the
documented Developer ID identity, so its signed local workflow remains valid.
Unsigned `xcodebuild` remains useful for compilation and standalone harnesses.

Messages are capped at 64 KiB; the helper hop has a three-second deadline and
the app's helper call a five-second deadline. Only a small operation allowlist
is forwarded. Mutations require the current server instance and a fresh request
UUID; Longhaul owns replay protection. Connected responses require a valid
snapshot bound to the current instance. Nodebay rejects stale revisions, unknown
versions, invalid progress/battery ranges and oversized collections. It polls
connected state every three seconds and backs off unavailable state to at most
once per minute. Transport failure clears stale private status. It does not
change Longhaul's protection.

## Control-location negotiation

The protocol remains version 1. A connected snapshot may include
`controlSurface: "nodebay"` or `controlSurface: "menuBar"`. Missing or null values
are the legacy Nodebay route; other values reject the response. Nodebay advertises
`capabilities: ["control-surface-v1"]` on `hello` and `status` requests only. The
helper permits at most 16 nonempty capability strings of at most 80 UTF-8 bytes on
those two read-only operations. Capabilities on mutations and unknown top-level
fields remain rejected.

Only a valid snapshot accepted by the revision cursor updates the route and the
`nodebay.longhaul.controlSurface` preference. Lower revisions and conflicting
routes at the same revision cannot change it. The accepted cursor and cached
visibility survive unavailable, restarted-but-unconnected, unpaired and
snapshot-free responses. A valid snapshot from a new relay instance establishes
a new revision epoch. A newly accepted legacy snapshot restores the Nodebay
route. An unknown cached preference falls back to Nodebay without overwriting
storage until a valid snapshot is accepted.

Control location affects only the notch button. It does not change automatic
protection, worker jobs, the important-notice preference, pairing or Open Longhaul.

## Supported Nodebay jobs

The helper reports actual validated process launches for document conversion,
image-copy optimization, FFmpeg processing, media downloads and STL-copy repair.
Version probes, media metadata inspection, STL inspection and Homebrew setup do
not count as protected output jobs. Titles are generic; input paths, URLs,
document contents and command arguments are not sent to Longhaul.

Each report contains a UUID job ID/incarnation, increasing sequence, actual worker
PID and birth time where the OS supplies it, phase and measured progress when
available. Active workers emit ten-second heartbeats; completion, failure and
explicit cancellation are terminal states. The helper retains terminal reports
for two minutes to cover a short reconnect. Longhaul must accept matching known
terminal reports after the worker PID has exited. The helper uses a separate
transport, so a companion timeout does not invalidate a conversion or HUD request.

These jobs currently report `checkpointCapable: false`. Nodebay does not claim it
can serialize arbitrary FFmpeg, downloader or converter state. Existing generated
file behavior and original-file protections are unchanged. Existing Nodebay quit
behavior can cancel its own helper workers. It never cancels other Longhaul jobs,
disconnects Longhaul from other adapters, or withdraws Longhaul's power assertion.

## Validation

2026-09-06 control-location revision: all three focused Python tests passed. The
compiled production client/view harness passed 44 checks, and the protocol/relay
harness passed 60 checks. Coverage includes valid, unknown and legacy wire values;
capability negotiation and relay bounds; persisted visibility and fallback;
lower/equal-revision rejection; transport errors, unpairing and restart; and a
poll superseded by a newer control response. A structural assertion verifies
that the parent stack conditionally removes the button and retains Settings
access. Fixtures use isolated preferences, mock transport and synthetic data;
no app, service or power action ran. Swift parsing and `git diff --check` passed.
These checks do not establish rendered removal, signed cross-app negotiation,
keyboard/VoiceOver behavior or the final distributed artifact.

Previous-build evidence supplied by the coordinated Longhaul task on 2026-09-06:
the earlier signed Nodebay binary with SHA-256 prefix `445320ec` passed native
moon/pause assertion release, sun/resume assertion reacquisition, idle sun state
and Open Longhaul routing. This is historical evidence for that binary, not
native verification of the new control-location change.

Direct-toggle revision: the focused Swift 5 harness compiles the actual views,
client, models and helper protocol, with an isolated stub for the unrelated notch
notice coordinator. All 24 new client checks passed, covering acknowledged state,
queued responses, duplicate clicks, stale snapshots, pause/resume direction,
unpaired/unavailable states, timeout, relay restart, revocation, failed requests
and immediate confirmation. The original protocol/worker harness also passed.
The fixtures inject transport, app location and monotonic time; no apps, services,
power actions or user settings are changed. They do not establish rendered icon
placement, focus, context-menu access or signed cross-app behavior.

2026-09-06: an arm64 Release compile completed successfully with signing disabled.
The full Python/harness suite passed 193 tests in 58.565 seconds, including the
new companion harness's 35 protocol/worker-policy checks. These checks did not
launch, install or replace either app, and made no power changes. The final
incremental arm64 Release compile also passed after the reconnect backoff and
compact-control layout refinement. Project plist validation and `git diff --check`
passed. The advisory design scan flagged `await Task.sleep` as synchronous I/O;
this was reviewed as a false positive because Swift's task sleep suspends without
blocking the main thread. The scan supports only macOS 26/27 profiles, so it does
not establish the preserved macOS 15 runtime compatibility.


Automated protocol/worker eligibility checks:

```sh
python3 -m unittest discover -s tests -p test_longhaul_companion.py -v
```

Full existing regression suite:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

For the control-location revision, verify signed negotiation with Longhaul,
complete icon-and-spacing removal, restoration after relaunch and connection loss,
legacy fallback, and reachable Settings/Open Longhaul in the real app. Repeat
pause/resume, pending/failed feedback and keyboard/VoiceOver/context-menu checks
on the final integrated binary. Earlier native and compiled evidence does not
establish the new rendered surface.

Broader companion acceptance includes: explicit pairing and revocation;
wrong UID/signature; relay/main-app restart and host staleness; control application;
two real concurrent jobs and cancellation; Nodebay exit while an independent
Longhaul job remains protected; persisted alert deduplication and notification
fallback; visible notch/settings controls; keyboard, VoiceOver, light/dark and
mixed-display camera safe areas. Compilation and the standalone harness do not
establish these live outcomes.

### Signed control-location verification, 2026-09-06

The coordinated native check used Longhaul candidate 19 and Nodebay's installed
1.2.0 (25) binary `6fc13f4472643d260e5ab736cc95257a01808efd29ad46a2c4e09d4c20187d8c`.
Selecting Menu Bar removed the entire Longhaul control and its gap from Nodebay;
selecting Nodebay restored the acknowledged sun icon. Both directions passed.
Closing Longhaul's window preserved its process and assertion; Open Longhaul
restored the unified window. Quitting Nodebay triggered Longhaul's reported
menu-bar fallback while the supervised checksum job and assertion continued.
Relaunching Nodebay restored the icon and cleared the fallback. Final preference
was Nodebay. These were bounded checks during a supervised job, not overnight
or physical lid testing. Direct menu-bar item interaction was unavailable through
the test UI surface; its fallback binding and displayed explanation were checked.

The supervised fixture subsequently exited successfully: all 150 checksum results
matched independently. All 72 active samples after acquisition retained the same
Longhaul process and assertion. The assertion was released after the normal
120-second grace (observed 122.9 seconds after fixture exit). A subsequent Longhaul
restart preserved Nodebay as the selected control location and reconnected.
No fixture worker or temporary hold remained. Automation and the user's completion
sleep preference were preserved. This remains a bounded local test.
