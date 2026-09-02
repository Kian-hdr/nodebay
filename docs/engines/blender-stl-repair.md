# Blender STL Repair provider

## Selected integration

Unmodified Blender **5.0.1**, build **a3db93c5b259**, installed separately at
`/Applications/Blender.app/Contents/MacOS/Blender`. Other versions are rejected
until tested. Nodebay does not download or redistribute Blender, its Python
runtime or its dependencies. The Nodebay-authored GPL-3.0 adapter uses BMesh's
documented normal recalculation, hole filling and triangulation functions.

Primary references checked during implementation:

- [Blender 5.0 BMesh operators](https://docs.blender.org/api/5.0/bmesh.ops.html).
- Installed Blender `--help`: background, factory startup, disable-autoexec,
  offline-mode, threads, Python script and Python-exit-code options.
- [Exact Blender 5.0.1 source](https://projects.blender.org/blender/blender/src/tag/v5.0.1).
- [Exact license text](https://raw.githubusercontent.com/blender/blender/v5.0.1/doc/license/GPL-license.txt).
- [Official 5.0 downloads](https://download.blender.org/release/Blender5.0/).

## Alternatives considered

| Engine | Assessment for this integration |
|---|---|
| Blender | Selected: installed native Apple Silicon companion, documented BMesh operations and CLI, no added Nodebay runtime, GPL-compatible adapter path |
| MeshLab / PyMeshLab | Viable broader filter suite, but requires a separate Python/native package setup; not selected or bundled. [Official installation](https://pymeshlab.readthedocs.io/en/latest/installation.html) |
| Manifold / OpenSCAD workflows | Strong solid/Boolean tools, not general automatic repair for arbitrary damaged triangle soups. Manifold explicitly limits its merge repair. [Official documentation](https://manifoldcad.org/docs/html/) |
| libigl-based tooling | Would require selecting/building a separate application around the library; not the smallest adapter for this Mac. Not integrated or tested |

“Smallest” here means Nodebay's additional deployment surface, not Blender's
download size. A clean Mac must install the companion. No engine has been forked
or modified, and no broader compatibility is implied.

## Permissions, health and failure

Local files only, obtained through Nodebay's existing file access/bookmarks.
Input: binary/ASCII STL. Output: binary STL and a local structural report.
No network permission or API credentials are needed. Runtime diagnostics check
the exact version through the same XPC allowlist. The Settings test repairs a
synthetic triangle and confirms that its open boundary is reported, then removes
only that disposable test result.

Missing/unsupported Blender, crashes, malformed data, timeout, cancellation,
output validation and storage failures produce recoverable errors. No fallback
upload occurs. See the [feature page](../features/stl-repair.md) for limits,
coordinate tolerance, unsupported defects and storage behavior.

## Licensing and corresponding source

Blender's distributed `text/copyright.txt` credits the Blender Foundation and
licenses Blender under GPL version 2 or, at the recipient's option, any later
version. Its upstream license text and copyright are recorded in
[THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md). That later-version grant
permits a GPL-3.0-compatible integration. Nodebay's governing license is unchanged.

| Component | Shipped by Nodebay | License / source obligation |
|---|---|---|
| Nodebay adapter and Swift integration | Source and signed app resources | Existing GPL-3.0; corresponding source is the matching Nodebay revision, including `scripts/stl_repair.py`, Swift sources and build files |
| Blender 5.0.1 | No; separately installed companion | GPL-2.0-or-later; obtain source at exact upstream tag/build above; Nodebay makes no binary-source offer for a binary it does not redistribute |
| Synthetic fixtures | Test source only | Original Nodebay test data under the repository GPL-3.0 license |

Bundling Blender later would require a fresh complete binary/dependency/source
distribution review. The notice check rejects a bundled Blender entry or detected
Blender vendor/runtime files under the checked packaging locations. No Blender
artwork or branding is reused. Blender Foundation does not endorse Nodebay.
