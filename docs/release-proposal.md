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

Publication is split into two approval gates because Apple notarization and stapling change the release archive and therefore its SHA-256. Publishing the current pre-notarization checksum would create a broken Homebrew cask.

### Phase 1: standalone source migration and notarization submission

1. Create public standalone `Kian-hdr/nodebay` without an initialized README or license.
2. Add it as `origin` and push the prepared `main` and `dev` branches, preserving complete history and metadata. Do not create the release tag yet.
3. Apply the proposed description, empty website, topics, issues setting, and current social preview.
4. Create the public release-tracking issue from `docs/github-migration-issue-draft.md`.
5. Add the approved archival notices to `Kian-hdr/boring.notch` and `Kian-hdr/homebrew-boring-notch-markitdown`, mark the former prerelease historical, then archive both repositories read-only.
6. Submit the exact Developer ID application to Apple notarization. If Apple credentials are not already configured, stop before authentication and request the repository owner's action.

Phase 1 does not create `Kian-hdr/homebrew-nodebay`, publish a tag or release, create a release PR, or expose a cask whose download URL does not exist.

### Phase 2: final release and Homebrew publication

After notarization succeeds, staple the ticket, recreate and reverify the ZIP, calculate the final checksum, update both cask copies, rerun the release and Homebrew checks, and present the exact final artifact and cask for a second approval. Only that second approval authorizes:

1. the `nodebay-v0.1.0` tag and GitHub release;
2. the `dev` to `main` release pull request, if a source difference exists at that time;
3. creation of public `Kian-hdr/homebrew-nodebay` and push of its prepared `main` branch;
4. public cask audit, install, launch, upgrade, and uninstall smoke tests.

## Approval gate

Before Phase 1, present the exact local branches, complete commit list, full diff artifact, tracked-file manifest, screenshots, notices, verification matrix, destinations, issue text, archival copy, and every external effect for explicit approval. Before Phase 2, present the final post-notarization archive, checksum, cask, release notes, proposed tag, PR state, and smoke-test plan for a second explicit approval.
