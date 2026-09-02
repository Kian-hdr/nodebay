# Reproducible release process

1. Start from reviewed `main`, set the version, and confirm the foundation and dependency locks.
2. Run `python3 scripts/generate_nodebay_notices.py --check` and all tests.
3. Package with a Developer ID identity:

   ```bash
   RELEASE_VERSION=1.0.0 \
   BUILD_NUMBER=21 \
   SIGNING_IDENTITY='Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)' \
   DEVELOPMENT_TEAM=HZWY8HT54D \
   ./scripts/package_homebrew_arm64.sh
   ```

4. Extract the signed app, create `Nodebay-1.0.0-arm64.dmg` with `Configuration/dmg/create_dmg.sh`, and sign the DMG with the same Developer ID identity. The visible DMG contents must be only `Nodebay.app` and the Applications shortcut.
5. Submit the DMG with the Keychain-backed notary profile:

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.0.0-arm64.dmg \
     --keychain-profile NodebayRelease \
     --wait
   ```

6. Staple and validate the accepted DMG, run Gatekeeper and disk-image verification, mount it read-only, and install and launch the contained app from `/Applications`.
7. Record the post-stapling SHA-256, update the cask, validate links and notices, and test installation on a clean Apple Silicon account.
8. Present the exact tag, artifact, checksum, cask, source commit, tests, screenshots, and notices for approval.
9. Only after approval, push `main` and `dev`, create the tag and release, then publish the tap.

The release source tag is the corresponding source for the GPL-3.0 binary. No release may contain an unlisted bundled dependency.
