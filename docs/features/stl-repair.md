# STL Repair

Nodebay repairs **copies** of local `.stl` models using an unmodified, separately
installed Blender 5.0.1 companion. This feature is new in Nodebay 1.1.0.
It is not online repair and has no upload path.

## Workflow

Add an STL to the shelf and choose **Repair STL**, or use its context menu.
Stacks expose **Repair Compatible Models**. Results are regular, persistent STL
files beside the source tile, or a new result stack beside the unchanged source
stack. Unsupported batch members are counted as skipped; failures do not discard
successful outputs. The report window shows progress and Cancel.

- **Safe Repair** (default): exact-coordinate vertex welding in the working mesh,
  duplicate/zero-area triangle removal, face-normal and winding recalculation.
  It does not close boundaries, remove disconnected components, simplify, remesh
  or rescale. Remaining topology defects produce a partial result.
- **Thorough Repair**: the same cleanup plus boundary filling and triangulation.
  Every invocation requires confirmation because intentional openings and large
  holes can be closed. No simplification, component removal or remeshing occurs.
- **Inspect Only**: reports structural measurements without writing a result STL.

Plugins & Engines → **3D Models** contains the mode, an off-by-default automatic
Safe Repair toggle, local test, report and installation guidance. The Overview
lists the provider once, with a Configure action, version, status and license.
Automatic repair, when explicitly enabled, never opts into Thorough Repair.

## Capabilities and limitations

The adapter accepts binary STL and a conservative ASCII STL grammar. It can
recover a binary header-count mismatch when all complete triangles are present,
or a missing ASCII footer. It rejects incomplete triangle records, invalid
coordinates, empty files and excessive counts. It does not guess geometry from
arbitrarily corrupted bytes.

Reports distinguish boundary edges, closed boundary loops, non-manifold edges
(more than two incident triangles), duplicate/degenerate faces, winding conflicts,
normal corrections, unique vertices, triangles and disconnected components.
STL repeats vertex coordinates by design and has no unreferenced vertex table;
the working mesh deduplicates exact vertices, but exported STL still repeats
them. A boundary loop is not evidence that the opening was unintended.

Self-intersections are **not tested or repaired**. Some non-manifold structures
cannot be safely repaired automatically and remain partial results. Disconnected
components are preserved. Normal corrections are repair operations, not a claim
that every surface was inferred correctly. No remaining measured defects is not
a printability guarantee. Validate in a slicer and, where appropriate, by printing.

Coordinates are not scaled. STL has no unit metadata; the importing application
must choose the original units. Blender uses float32 coordinates. Output bounds
must remain within `max(1e-6, maxAbsoluteInputCoordinate * 2e-7)` model units.
Changes beyond this tolerance are rejected, including removal of an outlying
degenerate triangle that would materially shrink the bounds.

## File safety and privacy

- Sources are read through existing bookmarks and copied into a private
  `Application Support/Nodebay/STLJobs/<UUID>/input.stl` staging directory.
- Blender receives only the staged copy, never the original path or filename.
- Readable, finite, non-degenerate binary output is validated again by Swift.
  Atomic hard-link promotion cannot overwrite an existing file. Names are
  `part-repaired.stl`, `part-repaired-2.stl`, etc., in persistent
  `Application Support/Nodebay/Repaired Models` inside the app container.
- Normal success, failure and cancellation remove the job's own staging folder.
  Abrupt machine termination can leave an orphan job folder; no startup cleanup
  currently removes such folders automatically.
- Removing the shelf reference does not delete the retained model. Normal shelf
  Undo, stacks, context menus and native dragging are reused. Quick Look depends
  on an installed macOS preview handler for STL; Nodebay does not ship one.
- Engine launch uses the allowlisted XPC path and structured arguments, with
  factory startup, automatic scripts disabled, offline mode and an OS network
  deny rule. No plugins, downloaded scripts, `.blend` files or shell commands
  are supplied. The pinned adapter script is shipped inside Nodebay's signed app.
- One repair process at a time; 32 MiB input, 200,000 triangles, 50 models per
  batch, two engine threads, 120/125-second CPU limits, 150-second wall watchdog,
  160-second outer timeout and a 2 GiB peak-RSS watchdog checked every 200 ms.
  The memory watchdog is sampled, not a hard allocation cap. File/count limits
  also bound work. Termination escalates to kill if the engine ignores cancellation.
- Engine output is bounded to 4 KiB and never surfaced as raw diagnostics.
  Reports contain counts/categories/version/duration, not geometry, names or
  paths. Source/result names are displayed only in the transient local UI.
  The persisted last result is fixed redacted text.

No online service is implemented. Local-only mode is always enabled. No claim
is made that all online services lack APIs; introducing one would require its
own API/terms/privacy review and explicit per-file upload consent.

See [engine selection and licensing](../engines/blender-stl-repair.md) and the
[verification report](../stl-repair-verification.md).
