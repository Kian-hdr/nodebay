# GitHub migration preflight

Checked live on 2026-08-17 before any external migration write.

## Local repository

- Path: `/Users/kian/Documents/Codex/BoringNotch-MarkItDown`
- Preserved implementation branch: `feature/nodebay` at `763f234efc5cc71dd45e16233b9fa0099fc53f89`
- Prepared stable branch: `main` at the release-candidate commit
- Prepared development branch: `dev` at the same release-candidate commit
- Preserved migration branch: `chore/nodebay-github-migration`
- Recoverable local tag: `nodebay-pre-github-migration-2026-08-17` at `763f234efc5cc71dd45e16233b9fa0099fc53f89`
- Working tree before this standalone-repository preparation: contained uncommitted Nodebay reliability, shelf, settings, HUD, and test changes; all were preserved and committed without squashing prior history
- Foundation: upstream `dev` commit `44dd999f70493da48209c99e9f873c47f2e55c83`
- History policy: no squash, rewrite, force-push, deletion, or upstream mutation proposed

## Current local remotes

- `upstream` fetch: `https://github.com/TheBoredTeam/boring.notch.git`
- `legacy-fork` fetch: `https://github.com/Kian-hdr/boring.notch.git`
- Push URLs for both legacy remotes: deliberately disabled
- `origin`: intentionally absent until `Kian-hdr/nodebay` is approved and created

The final requested layout is `origin -> Kian-hdr/nodebay`, with the historical sources retained as read-only fetch remotes. Creating the new public origin remains approval-gated.

## Owned GitHub repository

- Current: `Kian-hdr/boring.notch`
- Visibility: public
- Fork: yes, parent `TheBoredTeam/boring.notch`
- Default branch: `main`
- Development branch: `dev`
- `main` and `dev` protection: none
- Repository rulesets: none
- Open pull requests: 0
- Issues: disabled, so no open issue list exists
- Releases: one historical prerelease, `markitdown-v2.8-beta.0-markitdown.1`
- Historical assets:
  - `boringNotch-MarkItDown-2.8-beta.0-markitdown.1-arm64.zip`
  - `boringNotch-MarkItDown-2.8-beta.0-markitdown.1-arm64.zip.sha256`
- Existing tags and releases will remain historical records
- Repository secrets configured: none
- Repository environments configured: none
- Actions permission: enabled, all actions allowed, SHA pinning not required by repository policy
- Registered workflows reported by Actions API: 0, although ten inherited workflow files exist on `main`
- GitHub Pages: not configured
- Custom social preview: none
- Current website field: `https://theboring.name/`, controlled by upstream rather than Nodebay
- Current description: inherited Boring Notch description

## Identifiers and availability

- `Kian-hdr/nodebay`: live API returned 404 and the owner repository list contains no conflict
- `Kian-hdr/homebrew-nodebay`: live API returned 404 and the owner repository list contains no conflict
- Central Homebrew Cask code search for `cask "nodebay"`: no result
- Local cask token: `nodebay`
- Prepared tap checkout: `/Users/kian/Documents/Codex/homebrew-nodebay`
- Proposed tag: `nodebay-v0.1.0`
- Proposed archive: `Nodebay-0.1.0-arm64.zip`
- Proposed checksum file: `Nodebay-0.1.0-checksums.txt`
- Update-feed path inherited in source: `updater/appcast.xml`
- Nodebay app currently starts Sparkle with updates disabled and has no `SUFeedURL`

A 404 shows that the requested repository names are not currently visible or occupied in the authenticated namespace. GitHub still performs the authoritative final validation when the rename or repository creation is submitted.

## Actions and secrets referenced before migration

Inherited workflow files referenced these secret names. No secret values were printed:

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `CROWDIN_PROJECT_ID`
- `CROWDIN_PERSONAL_TOKEN`
- `PRIVATE_SPARKLE_KEY`
- `RELEASE_TOKEN`
- `HOMEBREW_TAP_TOKEN`
- automatic `GITHUB_TOKEN`

The inherited release workflow targeted upstream Boring Notch release URLs, appcast, and `TheBoredTeam/homebrew-boring-notch`. The inherited Crowdin workflow targeted the upstream localization project. Those publication paths are not safe for Nodebay and are removed on the migration branch.

The proposed Nodebay release workflow preserves the three existing signing secret names and introduces these notarization names:

- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

## Application identity and release state

- User-facing application name: Nodebay
- Bundle identifier: `theboringteam.boringnotch`, retained temporarily for migration safety
- XPC helper identifier: `theboringteam.boringnotch.BoringNotchXPCHelper`
- Minimum macOS: 15.0
- Architecture: Apple Silicon only
- Valid local signing identities: Developer ID Application and Apple Distribution for team `HZWY8HT54D`
- Current candidate: Developer ID signed, not notarized
- Current pre-notarization SHA-256: `b9deedc0cd4d2c111ac7d753cdb118f37a776f2ba301b76707d04a18a8c2e71a`
- Gatekeeper result: rejected as `Unnotarized Developer ID`, expected before Apple submission
- No notary credentials or stored notary profile are referenced by the repository
- No active Nodebay Sparkle feed is configured

## Homebrew state

- Prepared cask: `Casks/nodebay.rb`
- Proposed tap: `Kian-hdr/homebrew-nodebay`
- Proposed install commands: `brew tap Kian-hdr/nodebay && brew install --cask nodebay`, or `brew install --cask Kian-hdr/nodebay/nodebay`
- No public tap currently exists
- `brew style` and `brew audit` against the tap-qualified token are unavailable until the tap exists
- The cask cannot pass a public install smoke test until a notarized release URL exists

## External writes performed

None. No repository creation, push, rename, metadata update, issue, pull request, archive action, environment, secret, notarization, release, tap publication, merge, or upstream change has occurred.
