# Updating Nodebay

Nodebay 1.2.1 includes signed in-app updates. Open **About Nodebay** and choose **Check for Updates…**. The Software updates section has separate switches for automatic checks and automatic downloads. You can keep checking manually.

The first updater-enabled launch offers this choice. Older Nodebay releases forcibly disabled the updater, so their saved off value cannot reliably distinguish a preference from that old implementation. Nodebay asks once instead of silently changing it; an explicit choice made in this version is preserved.

Downloads install when you quit. A requested restart waits for active downloads, imports, conversions, engine installation, AI requests and unfinished drafts. Finish or cancel that work first. Shelf saves are flushed before termination. Installing an update retains the application's bundle identity, settings, Keychain entries and managed files; it does not clear data or replace your API key.

## Upgrade from 1.2.0 or earlier

Those releases cannot enable in-app updating remotely. Install the new verified release once from [GitHub Releases](https://github.com/Kian-hdr/nodebay/releases/latest), or update an existing Homebrew installation:

```bash
brew update
brew upgrade --cask --greedy Kian-hdr/nodebay/nodebay
```

The cask declares `auto_updates true`; `--greedy` explicitly includes it in Homebrew upgrades. After migration, use either Nodebay's updater or Homebrew. If Nodebay is already newer than the cask, keep the newer app. Never use `--zap`, remove Keychain items or reset the shelf as an update step.

## Verification and failures

The production feed is [Nodebay's signed appcast](https://raw.githubusercontent.com/Kian-hdr/nodebay/updates/stable/appcast.xml). The application requires Ed25519 signatures on the feed and archive before extraction, alongside the normal Developer ID verification. It does not use the original Boring Notch feed. Download errors or failed signature checks leave the installed app in place. Retry from About Nodebay or use a verified GitHub release; do not disable macOS security or signature checks.

Automatic checks contact GitHub, and update downloads use GitHub Releases. System profiling is disabled and no API keys, chat content or shelf files are sent. See [Privacy](../../PRIVACY.md#updates).

## Maintainer pipeline

Keep the signing key in protected local storage or a specifically provisioned release Keychain account outside the repository. Never place private key values in command arguments, source, CI logs, documentation or release assets. The application's public key is a build setting; changing it requires a reviewed key-rotation plan.

Use `scripts/nodebay_appcast.py prepare` on the final notarized/stapled ZIP. It invokes the pinned Sparkle generator and signer, then independently verifies archive and feed signatures against the public key. Supply the archive, version, monotonically increasing build, exact source commit, release notes, channel and a new output directory. See the command's `--help` for file-path and Keychain-account options.

Publish the matching immutable GitHub release asset first. Run the tool's `publish` command without `--publish` to validate the hosted release, source tag, anonymously downloaded bytes and signature. Set the expected current build to detect competing changes. Add `--publish` only for the authorized publication. The updates branch is pushed without force; stable and testing feeds live in separate directories. Bootstrap is explicit for an absent branch.

A stable publication must use a stable release, matching production feed and increasing build number. Testing uses a prerelease marked not latest; its feed can deliver the unchanged final production archive to prove an older test build upgrades into the production channel. Keep test assets out of stable releases and never replace published bytes. The GitHub workflow creates candidate artifacts only; it does not bypass the signing, notarization, acceptance and feed steps. See [release process](../release-process.md) and [verification matrix](../release-verification-matrix.md).
