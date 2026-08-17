from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETTINGS_CONTROLLER = (
    ROOT / "boringNotch/components/Settings/SettingsWindowController.swift"
).read_text()


class NodebaySettingsPresentationTests(unittest.TestCase):
    def test_settings_window_is_not_restored_automatically(self) -> None:
        self.assertIn("window.isRestorable = false", SETTINGS_CONTROLLER)
        self.assertIn("window.restorationClass = nil", SETTINGS_CONTROLLER)
        self.assertIn("window.disableSnapshotRestoration()", SETTINGS_CONTROLLER)
        self.assertNotIn("window.isRestorable = true", SETTINGS_CONTROLLER)

    def test_settings_window_requires_explicit_presentation(self) -> None:
        show_window = SETTINGS_CONTROLLER.split("func showWindow()", 1)[1].split(
            "override func close()", 1
        )[0]
        became_key = SETTINGS_CONTROLLER.split("func windowDidBecomeKey", 1)[1]

        self.assertIn("isExplicitPresentation = true", show_window)
        self.assertIn("guard isExplicitPresentation else", became_key)
        self.assertIn("window?.orderOut(nil)", became_key)
        self.assertIn("isExplicitPresentation = false", SETTINGS_CONTROLLER)


if __name__ == "__main__":
    unittest.main()
