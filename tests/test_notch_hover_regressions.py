"""Source-structure guards. Real hover/motion still requires running-app QA."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NotchHoverRegressionTests(unittest.TestCase):
    def test_pan_toggle_does_not_replace_notch_subtree(self):
        source = (ROOT / "boringNotch/ContentView.swift").read_text()
        self.assertNotRegex(source, r"\.conditionalModifier\([^\n]*(?:enableGestures|allowsNotchPan)")
        for direction in ("up", "down", "left", "right"):
            self.assertIn(f".panGesture(direction: .{direction}, enabled: notchPanEnabled", source)

    def test_disabled_pan_preserves_child_gestures(self):
        source = (ROOT / "boringNotch/extensions/PanGesture.swift").read_text()
        self.assertIn("including: enabled ? .all : .subviews", source)
        self.assertIn("guard enabled else { return }", source)
        self.assertIn("guard !Task.isCancelled, enabled else", source)
        self.assertIn("context.coordinator.update(enabled: enabled, action: action)", source)
        self.assertIn("return event", source)

    def test_hover_close_rechecks_pointer_and_animates(self):
        source = (ROOT / "boringNotch/ContentView.swift").read_text()
        helper = source.split("private func closeAfterHoverExit()", 1)[1].split("private func handleHover", 1)[0]
        self.assertLess(helper.index("guard !vm.isMouseHovering()"), helper.index("vm.close()"))
        self.assertIn("withAnimation(StandardAnimations.close)", helper)
        self.assertIn("!SharingStateManager.shared.preventNotchClose", helper)
        self.assertEqual(source.count("self.closeAfterHoverExit()"), 3)
        self.assertIn(".onDisappear { hoverTask?.cancel() }", source)

    def test_drag_activation_uses_closed_notch_region_until_open(self):
        source = (ROOT / "boringNotch/boringNotchApp.swift").read_text()
        drag_target = source.split("private func dragTarget(", 1)[1].split(
            "private func handleDragEntersNotchRegion", 1
        )[0]
        self.assertIn("if viewModel.notchState == .open", drag_target)
        self.assertIn("NotchDragRegion.closed", drag_target)
        self.assertIn("viewModel.effectiveClosedNotchHeight", drag_target)

        content = (ROOT / "boringNotch/ContentView.swift").read_text()
        # The global detector opens the notch using the bounded closed region.
        # The actual native drop destination stays on the notch layout instead
        # of being destroyed during the closed-to-open transition.
        self.assertNotIn("var dragDetector: some View", content)
        self.assertEqual(content.count("GeneralDropTargetDelegate("), 1)
        self.assertIn("DropProposal(operation: .copy)", content)

    def test_hover_geometry_rejects_points_above_the_display(self):
        source = (ROOT / "boringNotch/models/BoringViewModel.swift").read_text()
        helper = source.split("func isMouseHovering", 1)[1].split(
            "@discardableResult", 1
        )[0]
        self.assertIn("position.y <= frame.maxY", helper)

    def test_equalizer_popover_releases_notch_after_hover_exit(self):
        source = (ROOT / "boringNotch/components/Notch/NotchHomeView.swift").read_text()
        control = source.split("private struct EqualizerControl", 1)[1].split(
            "private struct EqualizerPopover", 1
        )[0]
        self.assertIn("isHoveringButton", control)
        self.assertIn("isHoveringPopover", control)
        self.assertIn("scheduleDismissalIfNeeded()", control)
        self.assertIn("Task.sleep(for: .milliseconds(350))", control)
        self.assertIn("SharingStateManager.shared.beginInteraction()", control)
        self.assertIn("SharingStateManager.shared.endInteraction()", control)
        self.assertIn("finishPopoverInteractionIfNeeded()", control)
        self.assertIn(".onDisappear", control)

    def test_closed_drag_region_geometry(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            executable = Path(temp_dir) / "notch-drag-region-harness"
            subprocess.run(
                [
                    "xcrun", "swiftc",
                    str(ROOT / "boringNotch/observers/DragDetector.swift"),
                    str(ROOT / "tests/NotchDragRegionHarness.swift"),
                    "-o", str(executable),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run(
                [str(executable)], check=True, capture_output=True, text=True
            )
            self.assertIn("NotchDragRegionHarness: PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
