import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
MUSIC_MANAGER = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
SPOTIFY_CONTROLLER = (
    ROOT / "boringNotch/MediaControllers/SpotifyController.swift"
).read_text()


class SpotifyStartupGuardTests(unittest.TestCase):
    def test_registry_only_refreshes_active_controllers(self):
        registry_start = MUSIC_MANAGER.index("private func initializeMediaSourceRegistry()")
        registry_end = MUSIC_MANAGER.index("private func setActiveController", registry_start)
        registry = MUSIC_MANAGER[registry_start:registry_end]

        self.assertIn("if controller.isActive()", registry)
        self.assertIn("await controller.updatePlaybackInfo()", registry)

    def test_spotify_queries_require_a_running_spotify_app(self):
        update_start = SPOTIFY_CONTROLLER.index("func updatePlaybackInfo() async")
        update_end = SPOTIFY_CONTROLLER.index("// MARK: - Private Methods", update_start)
        update_method = SPOTIFY_CONTROLLER[update_start:update_end]

        self.assertIn("guard isActive() else { return }", update_method)

    def test_spotify_commands_do_not_launch_or_resolve_spotify(self):
        command_start = SPOTIFY_CONTROLLER.index(
            "private func executeCommand(_ command: String) async"
        )
        command_end = SPOTIFY_CONTROLLER.index(
            "private func executeAndRefresh", command_start
        )
        command_method = SPOTIFY_CONTROLLER[command_start:command_end]

        self.assertIn("guard isActive() else { return }", command_method)


if __name__ == "__main__":
    unittest.main()
