"""Compile and execute the production source availability/selection policy."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MediaSessionSelectionTests(unittest.TestCase):
    def test_session_lifecycle_and_control_target_policy(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-media-selection-") as temp:
            binary = Path(temp) / "media-session-selection"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                str(ROOT / "boringNotch/models/PlaybackState.swift"),
                str(ROOT / "tests/MediaSessionSelectionHarness.swift"),
                "-o", str(binary),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.count("PASS "), 8, result.stdout)

    def test_now_playing_source_changes_do_not_borrow_metadata(self):
        source = (ROOT / "boringNotch/MediaControllers/NowPlayingController.swift").read_text()
        handler = source.split("    private func handleAdapterUpdate", 1)[1].split(
            "     private func fetchFavoriteStateIfSupported", 1
        )[0]
        helper_and_models = source.split("private extension NowPlayingController", 1)[1].split(
            "actor JSONLinesPipeHandler", 1
        )[0]
        # Execute the actual production reducer with only its process/observer
        # shell removed; these fixtures never touch system playback or apps.
        isolated = (
            'import Foundation\nfinal class AdapterStateHarness {\n'
            'var playbackState = PlaybackState(bundleIdentifier: "")\n'
            'var playbackIssue: String?\n'
            'func handleAdapterUpdate' + handler + '}\n'
            'private extension AdapterStateHarness' + helper_and_models
        )
        with tempfile.TemporaryDirectory(prefix="nodebay-adapter-state-") as temp:
            isolated_source = Path(temp) / "AdapterStateHarness.swift"
            isolated_source.write_text(isolated)
            binary = Path(temp) / "adapter-state"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                str(ROOT / "boringNotch/models/PlaybackState.swift"), str(isolated_source),
                str(ROOT / "tests/NowPlayingStateHarness.swift"), "-o", str(binary),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.count("PASS "), 4, result.stdout)


if __name__ == "__main__":
    unittest.main()
