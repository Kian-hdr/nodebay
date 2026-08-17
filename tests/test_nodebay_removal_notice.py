import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELF_VIEW = (ROOT / "boringNotch/components/Shelf/Views/ShelfView.swift").read_text(
    encoding="utf-8"
)
SHELF_STATE = (
    ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift"
).read_text(encoding="utf-8")
BORING_VIEW_MODEL = (
    ROOT / "boringNotch/models/BoringViewModel.swift"
).read_text(encoding="utf-8")


class RemovalNoticeContractTests(unittest.TestCase):
    def test_notice_expires_and_new_removal_restarts_timer(self):
        self.assertIn("private let removalNoticeDuration: Duration = .seconds(4)", SHELF_STATE)
        self.assertIn("removalNoticeDismissTask?.cancel()", SHELF_STATE)
        self.assertIn("scheduleRemovalNoticeDismissal()", SHELF_STATE)
        self.assertIn("try await Task.sleep(for: self.removalNoticeDuration)", SHELF_STATE)

    def test_notice_can_be_closed_or_swiped_away(self):
        self.assertIn('Image(systemName: "xmark")', SHELF_VIEW)
        self.assertIn("DragGesture(minimumDistance: 12)", SHELF_VIEW)
        self.assertIn("tvm.dismissRemovalNotice()", SHELF_VIEW)

    def test_opening_or_closing_notch_dismisses_notice(self):
        self.assertGreaterEqual(
            BORING_VIEW_MODEL.count("ShelfStateViewModel.shared.dismissRemovalNotice()"),
            2,
        )

    def test_dismissal_releases_undo_reference_without_touching_disk(self):
        dismissal = SHELF_STATE.split("func dismissRemovalNotice()", 1)[1].split("}", 1)[0]
        self.assertIn("lastRemoval = nil", dismissal)
        self.assertIn("canUndoRemoval = false", dismissal)
        self.assertNotIn("removeItem", dismissal)


if __name__ == "__main__":
    unittest.main()
