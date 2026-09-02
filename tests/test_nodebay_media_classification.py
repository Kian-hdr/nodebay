from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLASSIFIER = ROOT / "BoringNotch/components/Shelf/Services/MediaDownloadClassifier.swift"
HARNESS = ROOT / "tests/MediaDownloadClassifierHarness.swift"
SERVICE = (ROOT / "BoringNotch/components/Shelf/Services/MediaDownloaderService.swift").read_text()
SETTINGS = (ROOT / "BoringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift").read_text()


class MediaDownloadClassificationTests(unittest.TestCase):
    def test_classifier_behavior(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="nodebay-classifier-") as directory:
            executable = Path(directory) / "classifier-tests"
            subprocess.run(
                [swiftc, str(CLASSIFIER), str(HARNESS), "-o", str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("classifier fixtures passed", result.stdout)

    def test_settings_modes_and_safe_ffmpeg_behavior(self):
        for mode in ("Automatic (Recommended)", "Always Video", "Always Audio", "Ask Every Time"):
            self.assertIn(mode, CLASSIFIER.read_text())
        self.assertIn("if classification.kind == .audio && !ffmpegAvailable", SERVICE)
        self.assertIn("guard ffmpegAvailable else", SERVICE)
        self.assertIn("if override == .mp3 && !ffmpegAvailable", SERVICE)
        self.assertIn('Picker("Media selection"', SETTINGS)
        self.assertIn(".disabled(mode == .alwaysAudio && !downloads.ffmpegAvailable)", SETTINGS)

    def test_coordinator_behavior(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="nodebay-coordinator-tests-") as directory:
            executable = Path(directory) / "coordinator-tests"
            subprocess.run([
                swiftc, str(CLASSIFIER),
                str(ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift"),
                str(ROOT / "tests/MediaDownloaderHarness.swift"), "-o", str(executable),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True, timeout=30)
            self.assertIn("coordinator fixtures passed", result.stdout)

    def test_playlists_classify_each_item_and_allow_fixed_override(self):
        self.assertIn("case classifyPlaylistItems", SERVICE)
        self.assertIn("for (index, entry) in inspection.entries.enumerated()", SERVICE)
        self.assertIn("service.inspect(entry.url)", SERVICE)
        self.assertIn("MediaDownloaderService.classification(for: itemInspection)", SERVICE)
        self.assertIn("if let override", SERVICE)
        self.assertIn("Always use this media type", SERVICE)


if __name__ == "__main__":
    unittest.main()
