# Migration from Boring Notch

Nodebay is based on Boring Notch commit `44dd999f70493da48209c99e9f873c47f2e55c83` and preserves the complete reachable Git history, original authorship, GPL-3.0 license, and upstream attribution.

The first Nodebay release deliberately retains the legacy application bundle identifier `theboringteam.boringnotch` and selected internal target names. This avoids silently losing preferences, saved shelf bookmarks, login-item state, and Accessibility authorization. User-facing names, documentation, artifacts, and repository metadata are Nodebay.

Install only one `/Applications/Nodebay.app`. Old Boring Notch applications are not installed by the Nodebay cask. Removing an old app bundle does not remove files stored on the Nodebay shelf. A future bundle-identifier migration requires a signed migration helper and explicit testing; it must not be performed as a blind rename.

The historical repositories remain available read-only with archival notices linking to `https://github.com/Kian-hdr/nodebay`.
