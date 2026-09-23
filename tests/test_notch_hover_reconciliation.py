"""Execute the unchanged production dismissal policy without the app host."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HoverReconciliationTests(unittest.TestCase):
    def test_production_policy(self):
        source = (ROOT / "boringNotch/models/BoringViewModel.swift").read_text()
        policy = source[source.index("struct NotchHoverDismissal {"):]
        with tempfile.TemporaryDirectory() as folder:
            fixture = Path(folder) / "Policy.swift"
            fixture.write_text("import Foundation\n" + policy)
            executable = Path(folder) / "hover-tests"
            subprocess.run(["xcrun", "swiftc", str(fixture),
                            str(ROOT / "tests/NotchHoverReconciliationHarness.swift"),
                            "-o", str(executable)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("Hover reconciliation: PASS", result.stdout)

    def test_reconciliation_lifetime_and_real_pointer(self):
        source = (ROOT / "boringNotch/ContentView.swift").read_text()
        reconciliation = source.split(".task(id: vm.notchState)", 1)[1].split(".onReceive", 1)[0]
        self.assertIn("while !Task.isCancelled && vm.notchState == observedState", reconciliation)
        self.assertIn("let hovering = vm.isMouseHovering()", reconciliation)
        self.assertIn("hoverActivation.shouldOpen(", reconciliation)
        self.assertIn("vm.isMouseHovering(expanded: true)", reconciliation)
        self.assertNotIn(".onHover { hovering in", source.split(".onTapGesture", 1)[0])
        self.assertIn("interactionActive: preventsHoverClose", reconciliation)
        self.assertIn("catch { return }", reconciliation)
        for target in ["dragDetectorTargeting", "generalDropTargeting", "dropZoneTargeting"]:
            self.assertIn(f"vm.{target} = false", reconciliation)
        self.assertIn("guard !vm.isMouseHovering()", source)
        guards = source.split("private var preventsHoverClose", 1)[1].split("private func closeAfterHoverExit", 1)[0]
        for guard in ["isBatteryPopoverActive", "isRequestingAuthorization", "preventNotchClose",
                      "trackedMenus.isEmpty", "NSEvent.pressedMouseButtons", "helloAnimationRunning"]:
            self.assertIn(guard, guards)


if __name__ == "__main__":
    unittest.main()
