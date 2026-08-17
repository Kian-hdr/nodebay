# Nodebay 0.1.0 migration and publication proposal

This document is a draft only. It does not authorize any external action.

## Proposed destinations

- Current owned fork: `https://github.com/Kian-hdr/boring.notch`
- Renamed owned fork: `https://github.com/Kian-hdr/nodebay`
- Migration branch: `chore/nodebay-github-migration`
- Owned PR target: `Kian-hdr/nodebay:dev`
- Release tag: `nodebay-v0.1.0`
- Proposed tap: `https://github.com/Kian-hdr/homebrew-nodebay`
- Proposed install command: `brew install --cask Kian-hdr/nodebay/nodebay`
- Upstream remains: `https://github.com/TheBoredTeam/boring.notch`

No upstream issue or pull request is proposed as part of this migration.

## Proposed repository metadata

- Visibility: public, unchanged
- Default branch during migration: `main`, unchanged until a separate branch-policy decision
- Description: `A local-first macOS utility bay for the notch, with file stacks, conversion, downloads, media controls, and external-display support. Based on Boring Notch.`
- Website: empty until a controlled destination exists
- Issues: enabled
- Wiki: disabled
- Topics: `macos`, `swift`, `swiftui`, `notch`, `productivity`, `file-shelf`, `markdown`, `markitdown`, `yt-dlp`, `imageoptim`, `apple-silicon`, `open-source`
- Fork relationship: retained

## Proposed release assets

- `Nodebay-0.1.0-arm64.zip`
- `Nodebay-0.1.0-checksums.txt`
- GitHub-generated source archives for tag `nodebay-v0.1.0`
- Complete notices, privacy information, dependency manifest, and corresponding-source instructions in the source and app archive

The current pre-notarization archive SHA-256 is `3e073e3311159047246cc8de39810dd6b6506cfd8c1172287291dddde74183c1`. It is not a publishable final checksum because notarization and stapling will change the distributed archive.

Current signing identity: `Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)`.

## Proposed external operations

1. Push the local migration backup tag and `chore/nodebay-github-migration` branch to the owned fork.
2. Rename only `Kian-hdr/boring.notch` to `Kian-hdr/nodebay`.
3. Change local remotes so `origin` points to `Kian-hdr/nodebay` and `upstream` points to `TheBoredTeam/boring.notch`.
4. Verify the old GitHub URL redirects and fetch/push URLs resolve independently.
5. Apply the proposed description, empty website, topics, issues setting, and social preview.
6. Open the migration PR into the owned `dev` branch.
7. Create the Nodebay release-tracking issue.
8. Do not merge the PR unless merge is explicitly included in final approval.
9. Do not notarize, publish the release, create the tap, or publish the cask unless each is explicitly included in final approval.

## Approval gate

Before any operation above, present the final diff, commits, signed-build screenshots, notices, verification matrix, destinations, PR and issue text, release notes, cask, and every external effect for one explicit approval.
