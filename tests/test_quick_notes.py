from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "boringNotch/components/Shelf/Services/QuickNoteService.swift"
COORDINATOR = (ROOT / "boringNotch/components/Shelf/Services/QuickNotesCoordinator.swift").read_text()
SHELF = (ROOT / "boringNotch/components/Shelf/Views/ShelfView.swift").read_text()
MONITOR = (ROOT / "boringNotch/observers/DragDetector.swift").read_text()
APP = (ROOT / "boringNotch/boringNotchApp.swift").read_text()

class QuickNotesTests(unittest.TestCase):
    def test_executable_content_routing_storage_and_rich_text_fixtures(self):
        swiftc = shutil.which("swiftc")
        if not swiftc:
            self.skipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="nodebay-note-harness-") as directory:
            binary = Path(directory) / "tests"
            compile_result = subprocess.run([swiftc, str(SERVICE), str(ROOT / "tests/QuickNoteHarness.swift"), "-o", str(binary)], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("behavioral fixtures passed", result.stdout)

    def test_no_network_or_clipboard_polling_or_content_logs(self):
        for token in ("URLSession", "WKWebView", "Process(", "print(", "NSLog(", "Timer(", "changeCount"):
            self.assertNotIn(token, SERVICE.read_text() + COORDINATOR)
        self.assertIn("parser.shouldResolveExternalEntities = false", SERVICE.read_text())
        self.assertIn("func pasteIfSupported()", COORDINATOR)
        self.assertEqual(COORDINATOR.count("NSPasteboard.general"), 1)
        self.assertIn("locationCategory: \"Nodebay-managed Quick Notes\"", COORDINATOR)

    def test_normal_text_editor_paste_and_unhandled_events_pass_through(self):
        self.assertIn("NSApp.keyWindow?.firstResponder is NSTextView", APP)
        self.assertIn("vm.notchState == .open", APP)
        self.assertIn("openNotchRegion(for: window).contains(pointer)", APP)
        self.assertIn("monitor.shouldHandle?() == true", MONITOR)
        self.assertIn("guard monitor.handler?() == true else { return Unmanaged.passUnretained(event) }", MONITOR)
        self.assertIn("keyboardEventAutorepeat", MONITOR)

    def test_persistent_file_tiles_reuse_preview_drag_removal_and_undo(self):
        self.assertIn("ShelfItem(kind: .file(bookmark: try Bookmark(url: result.url).data))", COORDINATOR)
        self.assertNotIn("isTemporary: true", COORDINATOR)
        self.assertIn("ShelfSelectionModel.shared.selectSingle(item)", COORDINATOR)
        self.assertIn("proxy.scrollTo(id, anchor: .center)", SHELF)
        tile = (ROOT / "boringNotch/components/Shelf/Views/ShelfItemView.swift").read_text()
        self.assertIn("onQuickLook: showQuickLookForSelection", tile)
        self.assertIn("DraggableClickHandler(", tile)
        state = (ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift").read_text()
        remove = state.split("func remove(_ item: ShelfItem)")[1].split("private func scheduleRemovalNoticeDismissal")[0]
        self.assertIn("func undoLastRemoval()", remove)
        self.assertNotIn("removeItem(at:", remove)

    def test_transient_feedback_and_discoverable_editor(self):
        self.assertIn("Task.sleep(for: .seconds(3))", COORDINATOR)
        self.assertIn("quickNotes.dismissNotice()", SHELF)
        self.assertIn('accessibilityLabel("New Quick Note")', SHELF)
        self.assertIn("QuickNoteEditor", SHELF)
        self.assertIn("SharingStateManager.shared.beginInteraction()", COORDINATOR)

if __name__ == "__main__":
    unittest.main()
