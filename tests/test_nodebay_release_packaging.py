from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = (ROOT / "scripts/package_homebrew_arm64.sh").read_text()
VERIFY = (ROOT / "scripts/verify_release_artifact.sh").read_text()
RUNTIME_BUILD = (ROOT / "scripts/build_markitdown_runtime.sh").read_text()
CASK = (ROOT / "Casks/nodebay.rb").read_text()


class NodebayReleasePackagingTests(unittest.TestCase):
    def test_release_signs_every_nested_macho_and_code_bundle(self) -> None:
        self.assertIn('ENABLE_HARDENED_RUNTIME=YES', PACKAGE)
        self.assertIn('find "$app_stage/Contents" -type f', PACKAGE)
        self.assertIn("-name '*.framework'", PACKAGE)
        self.assertIn("-name '*.xpc'", PACKAGE)
        self.assertIn("-name '*.app'", PACKAGE)
        self.assertIn('--options runtime', PACKAGE)
        self.assertIn('--timestamp', PACKAGE)

    def test_artifact_verification_covers_notarization_requirements(self) -> None:
        for requirement in (
            "Developer ID signing authority",
            "hardened runtime flag",
            "designated requirement",
            "Timestamp=",
            "TeamIdentifier=",
            "stapler validate",
            "spctl --assess",
        ):
            self.assertIn(requirement, VERIFY)

    def test_generated_conflicts_are_removed_and_rejected(self) -> None:
        for marker in ("* 2", "__pycache__", "*.pyc"):
            self.assertIn(marker, RUNTIME_BUILD)
            self.assertIn(marker, VERIFY)

    def test_homebrew_cask_matches_final_notarized_artifact(self) -> None:
        self.assertIn('version "1.0.0"', CASK)
        self.assertIn(
            'sha256 "e33c60cbcf7aa2b80780b8f8c285e051fa94afe21f0b8db7cdaea9d8e0d4e772"',
            CASK,
        )
        self.assertIn("Nodebay-#{version}-arm64.dmg", CASK)
        self.assertIn('depends_on formula: "yt-dlp"', CASK)
        self.assertIn('depends_on formula: "ffmpeg"', CASK)
        self.assertIn('app "Nodebay.app"', CASK)
        self.assertNotIn("Boring Notch.app", CASK)


if __name__ == "__main__":
    unittest.main()
