# Upstream issue draft

Target: `TheBoredTeam/boring.notch`

## Proposal: reusable local processing, persistent stacks, and multi-display foundations

I have developed a migration-safe downstream edition called Nodebay, based on Boring Notch `dev` commit `44dd999f70493da48209c99e9f873c47f2e55c83`.

The branch adds several capabilities that may be useful to Boring Notch independently of the Nodebay rebrand:

- an extensible provider registry for local converters and companion engines
- isolated structured process execution through an XPC helper
- safe document-to-Markdown conversion using an unmodified Microsoft MarkItDown 0.1.7 runtime
- persistent file stacks with multi-item AppKit dragging
- reference-only shelf removal with Undo
- copy-first ImageOptim integration
- structured yt-dlp and FFmpeg companion workflows
- media-source and display registries
- reproducible Apple Silicon packaging and dependency-notice checks

The full downstream diff is intentionally broad because it also contains the Nodebay product identity. Before opening a pull request, I would like maintainer guidance on whether you prefer:

1. a small series containing only reusable infrastructure and safety fixes, or
2. a single reference pull request showing the complete downstream implementation.

No MarkItDown, yt-dlp, FFmpeg, or ImageOptim project is forked or modified. Original Boring Notch attribution and GPL-3.0 obligations are preserved.

