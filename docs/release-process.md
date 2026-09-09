# Reproducible release process

Nodebay **1.2.1 (26)** is the current release. Real API chat and the requested UI
checks are recorded in the [verification matrix](release-verification-matrix.md).
For each new version, follow the sequence below using a new tag and artifact names.
Never overwrite an existing release's tag or assets. Keep provider claims specific
to the verified API and restricted CLI paths; App Server streaming remains disabled.

1. Start from a reviewed, clean source commit containing the current remote `main` setup prompt and all intended candidate source changes. Set the version, confirm the foundation and dependency locks, and exclude private logs, credentials, generated runtimes and historical conflict duplicates. Preserve local changes outside the release snapshot.
2. Run `python3 scripts/generate_nodebay_notices.py --check` and all tests.
3. Package with a Developer ID identity:

   ```bash
   RELEASE_VERSION=1.2.1 \
   BUILD_NUMBER=26 \
   SIGNING_IDENTITY='Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)' \
   DEVELOPMENT_TEAM=HZWY8HT54D \
   ./scripts/package_homebrew_arm64.sh
   ```

4. Submit the signed ZIP with the Keychain-backed profile and require an `Accepted` result. Extract into a new staging directory, staple and validate `Nodebay.app`, then create the final ZIP containing only that stapled app. A ZIP cannot itself be stapled. Never overwrite a previously published archive.

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.2.1-arm64.zip \
     --keychain-profile NodebayRelease --wait
   # After Accepted, with the extracted app in your staging directory:
   xcrun stapler staple /path/to/staging/Nodebay.app
   xcrun stapler validate /path/to/staging/Nodebay.app
   ditto -c -k --keepParent /path/to/staging/Nodebay.app \
     /path/to/final/Nodebay-1.2.1-arm64.zip
   ```

5. Create `Nodebay-1.2.1-arm64.dmg` from the stapled app with `Configuration/dmg/create_dmg.sh`, and sign the DMG with the same Developer ID identity. The visible DMG contents must be only `Nodebay.app` and the Applications shortcut. Submit the DMG separately:

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.2.1-arm64.dmg \
     --keychain-profile NodebayRelease \
     --wait
   ```

6. Staple and validate the accepted DMG, run Gatekeeper and disk-image verification, mount it read-only, and install and launch the contained app from `/Applications`. Run `EXPECTED_VERSION=1.2.1 EXPECTED_BUILD=26 REQUIRE_NOTARIZED=1 ./scripts/verify_release_artifact.sh /path/to/final/Nodebay-1.2.1-arm64.zip` against the final ZIP as well. Record version/build, signature, timestamp, entitlements, exact hashes and notarization submission IDs for this candidate.
7. Record both post-stapling SHA-256 values, prepare the cask with the DMG checksum, validate links and notices, and test installation. Synchronize README, SETUP-PROMPT.md, privacy disclosures and release notes with the tested behavior. Keep the candidate marked unpublished until the release exists. Distinguish a same-account reinstall from a clean-account test; never use `--zap` for a data-preserving upgrade test.
8. Record the exact tag, artifacts, checksums, cask, source commit, tests, screenshots and notices covered by the owner's publication authorization. Existing explicit authorization remains valid for its stated scope.
9. Once the required verification passes, push the authorized `main` and `dev` updates, create the tag and release, then publish the tap.

10. Download both public assets again and compare the published checksums. Verify Homebrew upgrade, non-zap uninstall/reinstall, installed signature/staple, launch, data preservation and registration cleanup. Publish the result in the verification matrix without rewriting the release tag or artifact bytes.

The release source tag is the corresponding source for the GPL-3.0 binary. No
release may contain an unlisted bundled dependency. Longhaul remains a separate
optional companion: do not bundle its source or binaries, invent an installer
URL, or imply that Nodebay installs or pairs it automatically.

The existing GitHub release workflow produces a ZIP and does not implement the
complete DMG/cask sequence above. Supply the matching version and build inputs
and verify artifact coverage before using it for a new release; a workflow
upload alone is not evidence of notarization acceptance or a tested Homebrew
installation.
