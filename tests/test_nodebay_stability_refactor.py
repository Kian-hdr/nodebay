from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
APPLE_SCRIPT = (ROOT / "boringNotch/helpers/AppleScriptHelper.swift").read_text()
NOW_PLAYING = (ROOT / "boringNotch/MediaControllers/NowPlayingController.swift").read_text()
MUSIC_MANAGER = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
RUNTIME_ROOT = ROOT / "boringNotch/vendor/markitdown-runtime"


class NodebayStabilityRefactorTests(unittest.TestCase):
    def test_applescript_execution_is_serialized(self) -> None:
        self.assertIn('label: "app.nodebay.applescript"', APPLE_SCRIPT)
        self.assertIn("executionQueue.async", APPLE_SCRIPT)
        self.assertNotIn("Task.detached", APPLE_SCRIPT)

    def test_now_playing_stream_does_not_own_controller(self) -> None:
        self.assertIn("Task { [weak self, pipeHandler] in", NOW_PLAYING)
        self.assertIn("func shutdown()", NOW_PLAYING)
        self.assertNotIn("await self?.processJSONStream()", NOW_PLAYING)

    def test_media_manager_explicitly_stops_child_process(self) -> None:
        shutdown = MUSIC_MANAGER.index("(controller as? NowPlayingController)?.shutdown()")
        release = MUSIC_MANAGER.index("controllers.removeAll()", shutdown)
        self.assertLess(shutdown, release)

    def test_generated_runtime_contains_no_conflict_duplicates(self) -> None:
        if not RUNTIME_ROOT.exists():
            self.skipTest("Generated MarkItDown runtime is not present")
        conflicts = [
            path.relative_to(RUNTIME_ROOT)
            for path in RUNTIME_ROOT.rglob("*")
            if path.name.endswith(" 2") or path.name == "__pycache__" or path.suffix == ".pyc"
        ]
        self.assertEqual([], conflicts)


if __name__ == "__main__":
    unittest.main()
