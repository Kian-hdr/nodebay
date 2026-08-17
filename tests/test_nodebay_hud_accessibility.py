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

    def test_accessibility_monitor_recovers_a_missing_event_tap(self):
        monitor = INTERCEPTOR.split(
            "func startMonitoringAccessibilityAuthorization", 1
        )[1].split("func stopMonitoringAccessibilityAuthorization", 1)[0]
        self.assertIn("authorized && Defaults[.osdReplacement] && !isTapActive", monitor)
        self.assertIn("await start(promptIfNeeded: false)", monitor)

    def test_window_recreation_does_not_stop_media_key_interception(self):
        method = COORDINATOR.split("func applyOSDSources()", 1)[1].split(
            "func shouldShowSneakPeek", 1
        )[0]
        window_guard = method.index("notchSpace.windows.isEmpty")
        start = method.index("MediaKeyInterceptor.shared.start")
        self.assertLess(start, window_guard)
        self.assertNotIn("MediaKeyInterceptor.shared.stop()", method[window_guard:])


if __name__ == "__main__":
    unittest.main()
