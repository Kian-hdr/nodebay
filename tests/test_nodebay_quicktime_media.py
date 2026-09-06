import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONSTANTS = ROOT / "boringNotch/models/Constants.swift"
MUSIC = ROOT / "boringNotch/managers/MusicManager.swift"
CONTROLLER = ROOT / "boringNotch/managers/NodebayEqualizer.swift"
ENTITLEMENTS = ROOT / "boringNotch/boringNotch.entitlements"


class QuickTimeMediaSourceTests(unittest.TestCase):
    def test_quicktime_is_a_first_class_media_source(self):
        constants = CONSTANTS.read_text()
        music = MUSIC.read_text()
        self.assertIn("case quickTime", constants)
        self.assertIn('case .quickTime: "com.apple.QuickTimePlayerX"', constants)
        self.assertIn("newController = QuickTimeController()", music)

    def test_local_file_state_does_not_depend_on_system_now_playing(self):
        source = CONTROLLER.read_text()
        self.assertIn('tell application id "com.apple.QuickTimePlayerX"', source)
        self.assertIn("if playing of candidateDocument", source)
        self.assertIn("tell targetDocument", source)
        self.assertIn("return {name, playing, current time, duration, audio volume}", source)
        self.assertIn('audioCaptureBundleIdentifiers: [Self.bundleIdentifier]', source)
        self.assertIn("descriptor.atIndex(3)", source)

    def test_quicktime_automation_is_sandbox_allowlisted(self):
        with ENTITLEMENTS.open("rb") as handle:
            entitlements = plistlib.load(handle)
        allowed = entitlements["com.apple.security.temporary-exception.apple-events"]
        self.assertIn("com.apple.QuickTimePlayerX", allowed)

    def test_playing_quicktime_replaces_the_ambiguous_generic_source(self):
        source = MUSIC.read_text()
        self.assertIn("self.activeSourceID == .controller(.nowPlaying)", source)
        self.assertNotIn(
            "self.activeSourceID == .controller(.nowPlaying),\n                              !self.isPlaying",
            source,
        )

    def test_automatic_quicktime_override_returns_to_preferred_source_when_playback_stops(self):
        source = MUSIC.read_text()
        self.assertIn("isUsingAutomaticQuickTimeOverride", source)
        self.assertIn("!state.isPlaying", source)
        self.assertIn("self.setActiveControllerBasedOnPreference()", source)
        self.assertIn("isUsingAutomaticQuickTimeOverride = false", source)

    def test_quicktime_transport_scripts_compile_without_executing(self):
        source = CONTROLLER.read_text()
        methods = source.split("    private func executeDocumentCommand", 1)[1].split(
            "    private func publishUnavailable", 1
        )[0]
        snapshot = source.split('        let script = """', 1)[1].split("        do {", 1)[0]
        isolated = (
            "import Foundation\nfinal class QuickTimeScriptHarness {\n"
            'func snapshotScript() -> String { let script = """' + snapshot + "return script }\n"
            "func updatePlaybackInfo() async {}\n"
            "func executeDocumentCommand" + methods.replace("private func setDocumentProperty", "func setDocumentProperty")
            + "}\n"
        )
        with tempfile.TemporaryDirectory(prefix="nodebay-quicktime-scripts-") as temp:
            isolated_source = Path(temp) / "QuickTimeTransportMethods.swift"
            isolated_source.write_text(isolated)
            executable = Path(temp) / "quicktime-scripts"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                str(isolated_source), str(ROOT / "tests/QuickTimeScriptHarness.swift"),
                "-o", str(executable),
            ], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS 5 QuickTime scripts compile", result.stdout)


if __name__ == "__main__":
    unittest.main()
