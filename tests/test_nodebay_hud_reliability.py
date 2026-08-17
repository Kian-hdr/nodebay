from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
INTERCEPTOR = (ROOT / "boringNotch/observers/MediaKeyInterceptor.swift").read_text()
COORDINATOR = (ROOT / "boringNotch/BoringViewCoordinator.swift").read_text()
SETTINGS = (ROOT / "boringNotch/components/Settings/Views/OSDSettingsView.swift").read_text()
VOLUME = (ROOT / "boringNotch/components/OSD/Managers/XPC/VolumeManager.swift").read_text()
BRIGHTNESS = (ROOT / "boringNotch/components/OSD/Managers/XPC/BrightnessManager.swift").read_text()


class NodebayHUDReliabilityContractTests(unittest.TestCase):
    def test_authorization_states_are_for_current_signed_executable(self):
        self.assertIn("AXIsProcessTrusted()", INTERCEPTOR)
        self.assertIn("Authorized for this signed app", INTERCEPTOR)
        self.assertIn("Authorization changed; reauthorization required", INTERCEPTOR)
        self.assertIn("nodebayAccessibilityWasAuthorized", INTERCEPTOR)
        self.assertNotIn("tccutil", INTERCEPTOR)

    def test_event_tap_creation_failure_and_recovery_are_diagnostic(self):
        self.assertIn('"Failed",', INTERCEPTOR)
        self.assertIn("CGEvent.tapIsEnabled", INTERCEPTOR)
        self.assertIn("tapDisabledByTimeout", INTERCEPTOR)
        self.assertIn("tapDisabledByUserInput", INTERCEPTOR)
        self.assertIn('enabled ? "Active" : "Recovering"', INTERCEPTOR)

    def test_wake_activation_and_display_changes_recover_hud(self):
        for notification in (
            "NSWorkspace.didWakeNotification",
            "NSApplication.didBecomeActiveNotification",
            "NSApplication.didChangeScreenParametersNotification",
        ):
            self.assertIn(notification, COORDINATOR)
        self.assertIn("func recoverHUD()", COORDINATOR)

    def test_notch_window_recreation_does_not_stop_interception(self):
        method = COORDINATOR.split("func applyOSDSources()", 1)[1].split(
            "func shouldShowSneakPeek", 1
        )[0]
        self.assertLess(
            method.index("MediaKeyInterceptor.shared.start"),
            method.index("notchSpace.windows.isEmpty"),
        )

    def test_every_display_placement_mode_has_hud_routing(self):
        routing = COORDINATOR.split("func hudTargetScreenUUIDs", 1)[1].split(
            "private func hudDisplayDescription", 1
        )[0]
        for mode in (".all", ".builtIn", ".specific", ".main", ".followActive"):
            self.assertIn(f"case {mode}:", routing)
        self.assertIn("safeAreaInsets.top > 0", routing)
        self.assertIn("selectedScreenUUID", routing)
        self.assertIn("NSEvent.mouseLocation", routing)

    def test_recognized_events_pass_through_when_provider_is_unavailable(self):
        self.assertIn("guard canHandle(keyType, command: command) else", INTERCEPTOR)
        self.assertIn("return Unmanaged.passUnretained(cgEvent)", INTERCEPTOR)
        self.assertIn("VolumeManager.shared.canControlVolume", INTERCEPTOR)
        self.assertIn("VolumeManager.shared.canControlMute", INTERCEPTOR)
        self.assertIn("brightnessSupported", INTERCEPTOR)
        self.assertIn("keyboardBacklightSupported", INTERCEPTOR)
        self.assertIn("AudioObjectIsPropertySettable", VOLUME)
        self.assertIn("refreshSupport() async -> Bool", BRIGHTNESS)

    def test_external_providers_receive_keys_without_duplicate_interception(self):
        self.assertIn("BetterDisplayManager.shared.isBetterDisplayAvailable", INTERCEPTOR)
        self.assertIn("LunarManager.shared.isLunarAvailable", INTERCEPTOR)
        self.assertGreaterEqual(
            INTERCEPTOR.count("return Unmanaged.passUnretained(cgEvent)"), 6
        )

    def test_settings_exposes_non_sensitive_diagnostics_and_manual_recovery(self):
        for label in (
            'LabeledContent("HUD"',
            'LabeledContent("Accessibility"',
            'LabeledContent("Event tap"',
            'LabeledContent("Volume provider"',
            'LabeledContent("Brightness provider"',
            'LabeledContent("Active HUD display"',
            'LabeledContent("Last recoverable error"',
        ):
            self.assertIn(label, SETTINGS)
        self.assertIn('Button("Retry HUD")', SETTINGS)
        self.assertIn('Button("Open Accessibility Settings")', SETTINGS)
        self.assertIn("no key history", SETTINGS)


if __name__ == "__main__":
    unittest.main()
