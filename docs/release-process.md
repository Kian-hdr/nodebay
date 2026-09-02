# Reproducible release process

1. Start from reviewed `main`, set the version, and confirm the foundation and dependency locks.
2. Run `python3 scripts/generate_nodebay_notices.py --check` and all tests.
3. Package with a Developer ID identity:

   ```bash
   RELEASE_VERSION=1.1.0 \
   BUILD_NUMBER=24 \
   SIGNING_IDENTITY='Developer ID Application: Kian Konrad Tajbakhsh (HZWY8HT54D)' \
   DEVELOPMENT_TEAM=HZWY8HT54D \
   ./scripts/package_homebrew_arm64.sh
   ```

4. Submit the signed ZIP with the Keychain-backed profile and require an `Accepted` result. Extract into a new staging directory, staple and validate `Nodebay.app`, then create the final ZIP containing only that stapled app. A ZIP cannot itself be stapled. Never overwrite a previously published archive.

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.1.0-arm64.zip \
     --keychain-profile NodebayRelease --wait
   # After Accepted, with the extracted app in your staging directory:
   xcrun stapler staple /path/to/staging/Nodebay.app
   xcrun stapler validate /path/to/staging/Nodebay.app
   ditto -c -k --keepParent /path/to/staging/Nodebay.app \
     /path/to/final/Nodebay-1.1.0-arm64.zip
   ```

5. Create `Nodebay-1.1.0-arm64.dmg` from the stapled app with `Configuration/dmg/create_dmg.sh`, and sign the DMG with the same Developer ID identity. The visible DMG contents must be only `Nodebay.app` and the Applications shortcut. Submit the DMG separately:

   ```bash
   xcrun notarytool submit \
     build/nodebay-homebrew-arm64-release/Nodebay-1.1.0-arm64.dmg \
     --keychain-profile NodebayRelease \
     --wait
   ```

6. Staple and validate the accepted DMG, run Gatekeeper and disk-image verification, mount it read-only, and install and launch the contained app from `/Applications`. Run `REQUIRE_NOTARIZED=1 ./scripts/verify_release_artifact.sh /path/to/final/Nodebay-1.1.0-arm64.zip` against the final ZIP as well.
7. Record both post-stapling SHA-256 values, update the cask with the DMG checksum, validate links and notices, and test installation. Distinguish a same-account reinstall from a clean-account test; never use `--zap` for a data-preserving upgrade test.
8. Present the exact tag, artifact, checksum, cask, source commit, tests, screenshots, and notices for approval.
9. Only after approval, push `main` and `dev`, create the tag and release, then publish the tap.

10. Download both public assets again and compare the published checksums. Verify Homebrew upgrade, non-zap uninstall/reinstall, installed signature/staple, launch, data preservation and registration cleanup. Publish the result in the verification matrix without rewriting the release tag or artifact bytes.

The release source tag is the corresponding source for the GPL-3.0 binary. No release may contain an unlisted bundled dependency.
