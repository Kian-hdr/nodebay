import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
INTERCEPTOR = (ROOT / "boringNotch/observers/MediaKeyInterceptor.swift").read_text()
COORDINATOR = (ROOT / "boringNotch/BoringViewCoordinator.swift").read_text()
APP = (ROOT / "boringNotch/boringNotchApp.swift").read_text()


class NodebayHUDAccessibilityTests(unittest.TestCase):
    def test_main_process_checks_its_own_accessibility_grant(self):
        self.assertIn("AXIsProcessTrusted()", INTERCEPTOR)
        self.assertIn("AXIsProcessTrustedWithOptions(options)", INTERCEPTOR)
        self.assertNotIn(
            "XPCHelperClient.shared.isAccessibilityAuthorized()", INTERCEPTOR
        )
        self.assertNotIn(
            "XPCHelperClient.shared.ensureAccessibilityAuthorization", INTERCEPTOR
        )

    def test_hud_starts_main_process_authorization_monitor(self):
        self.assertIn(
            "MediaKeyInterceptor.shared.startMonitoringAccessibilityAuthorization()",
            COORDINATOR,
        )
        self.assertNotIn(
            "XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()",
            COORDINATOR,
        )

    def test_app_stops_main_process_authorization_monitor(self):
        self.assertIn(
            "MediaKeyInterceptor.shared.stopMonitoringAccessibilityAuthorization()", APP
        )

    def test_event_tap_start_uses_main_process_grant(self):
        start = INTERCEPTOR.index("func start(promptIfNeeded: Bool = false) async")
        end = INTERCEPTOR.index("func stop()", start)
        start_method = INTERCEPTOR[start:end]

        self.assertIn("let authorized = AXIsProcessTrusted()", start_method)
        self.assertNotIn("XPCHelperClient.shared", start_method)


if __name__ == "__main__":
    unittest.main()
