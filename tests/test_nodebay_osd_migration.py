import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
COORDINATOR = (ROOT / "boringNotch/BoringViewCoordinator.swift").read_text(
    encoding="utf-8"
)


class OSDPreferenceMigrationContractTests(unittest.TestCase):
    def test_legacy_hud_preferences_are_migrated_before_osd_startup(self):
        initializer = COORDINATOR.split("private init()", 1)[1]
        self.assertIn("Self.migrateLegacyOSDPreferencesIfNeeded()", initializer)
        self.assertLess(
            initializer.index("Self.migrateLegacyOSDPreferencesIfNeeded()"),
            initializer.index("if Defaults[.osdReplacement]"),
        )

    def test_all_renamed_hud_keys_are_covered(self):
        for legacy, current in (
            ("hudReplacement", "osdReplacement"),
            ("inlineHUD", "inlineOSD"),
            ("showOpenNotchHUD", "showOpenNotchOSD"),
            ("showOpenNotchHUDPercentage", "showOpenNotchOSDPercentage"),
            ("showClosedNotchHUDPercentage", "showClosedNotchOSDPercentage"),
        ):
            self.assertIn(f'(legacy: "{legacy}", current: "{current}")', COORDINATOR)

    def test_existing_new_preferences_are_not_overwritten(self):
        self.assertIn(
            "where defaults.object(forKey: mapping.current) == nil", COORDINATOR
        )
        self.assertIn('let migrationKey = "nodebayDidMigrateLegacyOSDPreferences"', COORDINATOR)


if __name__ == "__main__":
    unittest.main()
