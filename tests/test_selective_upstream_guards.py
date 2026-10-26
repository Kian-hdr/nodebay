"""Run production Swift fragments with deterministic inputs; no app/camera launch."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def braced(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[start:cursor], source[opening + 1:cursor - 1]


@unittest.skipUnless(shutil.which("xcrun"), "Requires macOS Swift/AppKit")
class SelectiveUpstreamGuardsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="nodebay-guard-tests-")
        root = Path(cls.temp.name)
        app = (ROOT / "boringNotch/boringNotchApp.swift").read_text()
        _, display_body = braced(app, "if !Defaults[.showOnAllDisplays] {\n            let viewModel = self.vm")
        music = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
        anchor, _ = braced(music, "if timeChanged || playbackRateChanged || activePlaybackChanged")
        estimate, _ = braced(music, "public func estimatedPlaybackPosition")
        harness = r'''
import AppKit
// Controlled screen inventory, exercising the actual launch branch below.
enum NSScreen {
    static var main: Int? = nil
    static var screens: [Int] = []
}
final class DisplayHarness {
    let vm = 7
    var window: Int?
    var creations = 0
    var adjustments = 0
    func createBoringNotchWindow(for screen: Int, with: Int) -> Int {
        creations += 1
        return screen
    }
    func adjustWindowPosition(changeAlpha: Bool) { adjustments += 1 }
    func launchBranch() {
DISPLAY_BODY
    }
}
struct State { var lastUpdated: Date }
final class TimelineHarness {
    var publications = 0
    var timestampDate = Date(timeIntervalSince1970: 100) {
        didSet { publications += 1 }
    }
    var elapsedTime = 10.0
    var songDuration = 500.0
    var playbackRate = 1.0
    var isPlaying = true
    func apply(_ state: State, _ timeChanged: Bool = false,
               _ playbackRateChanged: Bool = false,
               _ activePlaybackChanged: Bool = false,
               _ activeBundleChanged: Bool = false) {
ANCHOR
    }
ESTIMATE
}
let command = CommandLine.arguments[1]
switch command {
case "missing-audio":
    AudioPlayer().play(fileName: "Missing_Nodebay_Test_Resource_f80c6a", fileExtension: "wav")
case "no-display":
    let harness = DisplayHarness()
    harness.launchBranch()
    precondition(harness.creations == 0 && harness.window == nil)
    precondition(harness.adjustments == 1)
    NSScreen.screens = [42]
    harness.launchBranch()
    precondition(harness.window == 42 && harness.creations == 1)
    NSScreen.main = 99
    harness.launchBranch()
    precondition(harness.window == 99 && harness.creations == 2)
case "timeline":
    let timeline = TimelineHarness()
    let event = State(lastUpdated: Date(timeIntervalSince1970: 105))
    timeline.apply(event)
    precondition(timeline.publications == 0)
    precondition(timeline.estimatedPlaybackPosition(at: event.lastUpdated) == 15)
    // No-op metadata streams must not move the anchor backwards to 10.
    timeline.apply(State(lastUpdated: Date(timeIntervalSince1970: 106)))
    precondition(timeline.publications == 0)
    precondition(timeline.estimatedPlaybackPosition(at: Date(timeIntervalSince1970: 106)) == 16)
    timeline.elapsedTime = 60
    timeline.apply(event, true)
    precondition(timeline.publications == 1)
    precondition(timeline.estimatedPlaybackPosition(at: event.lastUpdated) == 60)
    timeline.playbackRate = 2
    timeline.apply(event, false, true)
    precondition(timeline.publications == 2)
    precondition(timeline.estimatedPlaybackPosition(at: Date(timeIntervalSince1970: 106)) == 62)
    timeline.isPlaying = false
    timeline.apply(event, false, false, true)
    precondition(timeline.publications == 3)
    precondition(timeline.estimatedPlaybackPosition(at: Date(timeIntervalSince1970: 110)) == 60)
    timeline.isPlaying = true
    timeline.apply(State(lastUpdated: Date(timeIntervalSince1970: 110)), false, false, true)
    precondition(timeline.publications == 4)
    precondition(timeline.estimatedPlaybackPosition(at: Date(timeIntervalSince1970: 110)) == 60)
    timeline.apply(event, false, false, false, true)
    precondition(timeline.publications == 5)
default:
    fatalError("Unknown test")
}
print("PASS: \(command)")
'''.replace("DISPLAY_BODY", display_body).replace("ANCHOR", anchor).replace("ESTIMATE", estimate)
        main = root / "main.swift"
        main.write_text(harness)
        cls.binary = root / "guards"
        build = subprocess.run(["xcrun", "swiftc", str(ROOT / "boringNotch/helpers/AudioPlayer.swift"),
                        str(main), "-o", str(cls.binary)], timeout=90,
                       capture_output=True, text=True)
        if build.returncode:
            cls.temp.cleanup()
            raise RuntimeError(build.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def execute(self, name):
        result = subprocess.run([str(self.binary), name], check=True, timeout=10,
                                capture_output=True, text=True)
        self.assertIn("PASS: " + name, result.stdout)

    def test_missing_audio_resource_is_ignored(self):
        self.execute("missing-audio")

    def test_empty_screen_inventory_and_display_fallbacks(self):
        self.execute("no-display")

    def test_timeline_noops_seeks_rates_pause_resume_and_source_changes(self):
        self.execute("timeline")


if __name__ == "__main__":
    unittest.main()
