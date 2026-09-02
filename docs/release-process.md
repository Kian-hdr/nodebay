# Reproducible release process

1. Start from reviewed `main`, set the version, and confirm the foundation and dependency locks.
2. Run `python3 scripts/generate_nodebay_notices.py --check` and all tests.
3. Package with a Developer ID identity:

   ```bash
   RELEASE_VERSION=1.0.0 \
   BUILD_NUMBER=21 \
   BUILD_NUMBER=3 \
   SIGNING_IDENTITY='Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)' \
   DEVELOPMENT_TEAM=HZWY8HT54D \
   ./scripts/package_homebrew_arm64.sh
   ```

4. Submit the ZIP with the Keychain-backed notary profile:

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.0.0-arm64.zip \
     --keychain-profile NodebayRelease \
     --wait
   ```

5. Extract the accepted ZIP, run `xcrun stapler staple Nodebay.app`, recreate the ZIP, and run `REQUIRE_NOTARIZED=1 ./scripts/verify_release_artifact.sh`.
6. Record the SHA-256, update the cask, validate links and notices, and test installation on a clean Apple Silicon account.
7. Present the exact tag, artifact, checksum, cask, source commit, tests, screenshots, and notices for approval.
8. Only after approval, push `main` and `dev`, create the tag and release, then publish the tap.

The release source tag is the corresponding source for the GPL-3.0 binary. No release may contain an unlisted bundled dependency.
