# Nodebay 0.1.0 migration and publication proposal

This document is a draft only. It does not authorize any external action.

## Proposed destinations

- New canonical repository: `https://github.com/Kian-hdr/nodebay`
- Repository type: standalone public repository, not a GitHub fork
- Stable branch: `main`
- Development branch: `dev`
- Release PR target: `Kian-hdr/nodebay:main` from `Kian-hdr/nodebay:dev`
- Release tag: `nodebay-v0.1.0`
- Proposed tap: `https://github.com/Kian-hdr/homebrew-nodebay`
- Proposed install command: `brew install --cask Kian-hdr/nodebay/nodebay`
- Historical upstream remains: `https://github.com/TheBoredTeam/boring.notch`
- Obsolete owned repositories to archive: `Kian-hdr/boring.notch` and `Kian-hdr/homebrew-boring-notch-markitdown`

No upstream issue or pull request is proposed as part of this migration.

## Proposed repository metadata

- Visibility: public
- Default branch: `main`
- Description: `A local-first macOS utility bay for the notch, with file stacks, conversion, downloads, media controls, and external-display support. Based on Boring Notch.`
- Website: empty until a controlled destination exists
- Issues: enabled
- Wiki: disabled
- Topics: `macos`, `swift`, `swiftui`, `notch`, `productivity`, `file-shelf`, `markdown`, `markitdown`, `yt-dlp`, `imageoptim`, `apple-silicon`, `open-source`
- Fork relationship: none; provenance is preserved through complete Git history and visible attribution

## Proposed release assets

- `Nodebay-0.1.0-arm64.zip`
- `Nodebay-0.1.0-checksums.txt`
- GitHub-generated source archives for tag `nodebay-v0.1.0`
- Complete notices, privacy information, dependency manifest, and corresponding-source instructions in the source and app archive

The current pre-notarization archive SHA-256 is `b9deedc0cd4d2c111ac7d753cdb118f37a776f2ba301b76707d04a18a8c2e71a`. It is not a publishable final checksum because notarization and stapling will change the distributed archive.

Current signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`.

## Proposed external operations

1. Create public standalone `Kian-hdr/nodebay` without an initialized README or license.
2. Add it as `origin` and push the prepared `main` and `dev` branches plus the approved Nodebay tag, preserving history and metadata.
3. Apply the proposed description, empty website, topics, issues setting, and social preview.
4. Create public `Kian-hdr/homebrew-nodebay`, push its prepared `main`, and set its description.
5. Add archival notices to `Kian-hdr/boring.notch` and `Kian-hdr/homebrew-boring-notch-markitdown`, mark the former prerelease historical, then archive both repositories read-only.
6. Create the Nodebay release-tracking issue and, if approved, the `dev` to `main` release pull request.
7. Submit the exact Developer ID artifact to Apple notarization, staple it, recreate and reverify the archive, and update the cask to the final checksum.
8. Publish the approved GitHub release and tap only after the final post-notarization checksum is known.

## Approval gate

Before any operation above, present the final diff, commits, signed-build screenshots, notices, verification matrix, destinations, PR and issue text, release notes, cask, and every external effect for one explicit approval.
