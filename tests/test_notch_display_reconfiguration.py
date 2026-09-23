"""Runs actual geometry/routing bodies with deterministic window/service doubles.

The extracted bodies are unchanged production Swift. Only unrelated lifetime,
media, and real AppKit window construction are substituted. This does not prove
physical monitor hotplug or native rendered correctness.
"""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODEL = "boringNotch/models/BoringViewModel.swift"
APP = "boringNotch/boringNotchApp.swift"
BASELINE = "8147acb"


def member(source, marker):
    start = source.index(marker)
    line_start = source.rfind("\n", 0, start) + 1
    opening = source.index("{", start)
    depth = 1
    index = opening + 1
    while depth:
        depth += (source[index] == "{") - (source[index] == "}")
        index += 1
    return source[line_start:index]


def property_source(source, name):
    match = re.search(r"(?m)^    [^\n]*\bvar " + name + r"\b[^\n]*", source)
    if not match:
        raise AssertionError("Missing production property " + name)
    return member(source, "var " + name) if "{" in match[0] else match[0]


def fixture_source(model, app, sizing):
    properties = "\n".join(property_source(model, name)
                           for name in ("notchState", "screenUUID", "notchSize", "closedNotchSize"))
    initializer = member(model, "init(screenUUID:").split("        Publishers.", 1)[0] + "    }"
    model_methods = [member(model, "func " + name + "(") for name in ("open", "close", "destroy")]
    if "func refreshDisplayGeometry(" in model:
        model_methods.append(member(model, "func refreshDisplayGeometry("))
    app_methods = [member(app, "func " + name + "(") for name in
                   ("positionWindow", "resolvedSingleDisplay", "adjustWindowPosition",
                    "screenConfigurationDidChange", "cleanupWindows", "onScreenLocked", "onScreenUnlocked")]
    constants = "\n".join(re.findall(r"(?m)^let (?:shadowPadding|openNotchSize|windowSize):[^\n]+", sizing))
    return f'''import Combine
import CoreGraphics
import Foundation
{constants}
@MainActor final class BoringViewModel: NSObject {{
    struct AnimationLibrary {{ let animation = 0 }}
    let animationLibrary = AnimationLibrary()
    let animation: Int
    let coordinator = FixtureCoordinator.shared
    var generalDropTargeting = false
    var edgeAutoOpenActive = false
    var isBatteryPopoverActive = false
    var cancellables = Set<AnyCancellable>()
{properties}
{initializer}
{chr(10).join(model_methods)}
}}
@MainActor final class AppDelegate: NSObject {{
    var windows: [String: NSWindow] = [:]
    var viewModels: [String: BoringViewModel] = [:]
    var window: NSWindow?
    let vm = BoringViewModel()
    let coordinator = FixtureCoordinator.shared
    var previousScreens: [NSScreen]? = NSScreen.screens
    var screenConfigurationTask: DispatchWorkItem?
    var isScreenLocked = false
    var windowScreenDidChangeObserver: Any?
    var dragRefreshes = 0
    func setupDragDetectors() {{ dragRefreshes += 1 }}
    func enableSkyLightOnAllWindows() {{}}
    func disableSkyLightOnAllWindows() {{}}
    func createBoringNotchWindow(for screen: NSScreen, with model: BoringViewModel) -> NSWindow {{
        let window = BoringNotchSkyLightWindow()
        NSApp.windows.append(window)
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return window
    }}
{chr(10).join(app_methods)}
}}
'''


class NotchDisplayReconfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="nodebay-display-tests-")
        cls.folder = Path(cls.directory.name)
        cls.current = cls.compile_sources("current", (ROOT / MODEL).read_text(), (ROOT / APP).read_text(),
                                          (ROOT / "boringNotch/sizing/matters.swift").read_text())
        # Normal regressions also work in a source ZIP or shallow CI checkout.
        # Historical reproduction is additionally run when the released object
        # is available, without fetching or modifying repository state.
        baseline_available = subprocess.run(
            ["git", "cat-file", "-e", BASELINE + "^{commit}"], cwd=ROOT,
            capture_output=True, timeout=10,
        ).returncode == 0
        cls.baseline = None
        if baseline_available:
            def historical(path):
                return subprocess.check_output(["git", "show", BASELINE + ":" + path], cwd=ROOT, text=True)
            cls.baseline = cls.compile_sources("baseline", historical(MODEL), historical(APP),
                                               historical("boringNotch/sizing/matters.swift"))

    @classmethod
    def compile_sources(cls, name, model, app, sizing):
        source = cls.folder / (name + ".swift")
        source.write_text(fixture_source(model, app, sizing))
        executable = cls.folder / name
        result = subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "5", "-strict-concurrency=targeted",
             str(source), str(ROOT / "tests/NotchDisplayReconfigurationHarness.swift"), "-o", str(executable)],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        return executable

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_case(self, case, executable=None):
        result = subprocess.run([str(executable or self.current), case], capture_output=True, text=True, timeout=15)
        return result

    def assert_case(self, case):
        result = self.run_case(case)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Display reconfiguration checks passed", result.stdout)

    def test_open_hotplug_follow_active_unlock_and_height_refresh(self):
        self.assert_case("open-route")

    def test_closed_geometry_refresh_does_not_invoke_close_side_effects(self):
        self.assert_case("closed-refresh")

    def test_single_display_reconciliation_retains_host_and_model(self):
        self.assert_case("single-reconciliation")

    def test_all_displays_retain_existing_hosts_and_retire_only_removed_display(self):
        self.assert_case("all-reconciliation")

    def test_same_frame_scaling_change_refreshes_once_per_notification_burst(self):
        self.assert_case("same-frame-scale")

    def test_swapped_display_frame_associations_reposition_existing_hosts(self):
        self.assert_case("arrangement-swap")

    def test_transient_empty_display_list_restores_same_open_host(self):
        self.assert_case("empty-restoration")

    def test_transient_empty_display_list_restores_all_open_hosts(self):
        self.assert_case("empty-all-restoration")

    def test_appkit_constrained_canvas_is_restored_when_repositioning(self):
        self.assert_case("canvas-repair")

    def test_orphaned_window_and_previous_display_mode_are_retired(self):
        self.assert_case("orphan-window")

    def test_released_baseline_reproduces_clipped_open_state(self):
        if self.baseline is None:
            self.skipTest("Released baseline object is unavailable in this checkout")
        result = self.run_case("open-route", self.baseline)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Open hotplug size must remain 640x190", result.stdout)

    def test_released_baseline_recreates_unaffected_host(self):
        if self.baseline is None:
            self.skipTest("Released baseline object is unavailable in this checkout")
        result = self.run_case("single-reconciliation", self.baseline)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("retain an unaffected single-display host", result.stdout)


if __name__ == "__main__":
    unittest.main()
