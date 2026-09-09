"""Exercise real controller lifecycle with a private, deterministic helper process."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MediaDiscoveryRecoveryTests(unittest.TestCase):
    def test_helper_restart_permissions_fragmented_metadata_and_shutdown(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-media-recovery-") as temp:
            binary = Path(temp) / "media-recovery"
            sources = [
                "boringNotch/models/PlaybackState.swift",
                "boringNotch/helpers/AppleScriptHelper.swift",
                "boringNotch/MediaControllers/MediaControllerProtocol.swift",
                "boringNotch/MediaControllers/NowPlayingController.swift",
                "tests/MediaDiscoveryRecoveryHarness.swift",
            ]
            subprocess.run(["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                            *[str(ROOT / source) for source in sources], "-o", str(binary)],
                           check=True, capture_output=True, text=True, timeout=30)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stdout.count("PASS "), 7, result.stdout)

    def test_bundled_framework_accepts_real_untitled_clients(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-media-metadata-") as temp:
            binary = Path(temp) / "media-metadata"
            frameworks = ROOT / "mediaremote-adapter"
            subprocess.run([
                "xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=15.0",
                str(ROOT / "tests/MediaRemoteMetadataHarness.m"),
                "-framework", "Foundation", "-F", str(frameworks),
                "-framework", "MediaRemoteAdapter", f"-Wl,-rpath,{frameworks}", "-o", str(binary),
            ], check=True, capture_output=True, text=True, timeout=30)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.stdout.count("PASS "), 2, result.stdout)

    def test_actual_discovery_is_not_gated_by_a_synthetic_player(self):
        source = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
        self.assertNotIn("checkDeprecationStatus()", source)
        self.assertIn("self?.setActiveControllerBasedOnPreference()", source)
        self.assertIn("func refreshMediaSources()", source)

    def test_app_permissions_are_not_silently_converted_to_empty_metadata(self):
        for name in ["SpotifyController", "AppleMusicController"]:
            source = (ROOT / f"boringNotch/MediaControllers/{name}.swift").read_text()
            self.assertIn("on error errorMessage number errorNumber", source)
            self.assertIn("error errorMessage number errorNumber", source)
            self.assertIn("MediaPlaybackIssue.message(for: error", source)


if __name__ == "__main__":
    unittest.main()
