import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELF_ITEM_VIEW = (
    ROOT / "boringNotch/components/Shelf/Views/ShelfItemView.swift"
).read_text(encoding="utf-8")


class ShelfQuickLookContractTests(unittest.TestCase):
    def test_clicked_tile_becomes_first_responder(self):
        self.assertIn("override var acceptsFirstResponder: Bool { true }", SHELF_ITEM_VIEW)
        self.assertIn("makeShelfItemFirstResponder(self)", SHELF_ITEM_VIEW)

        for relative_path in (
            "boringNotch/components/Notch/BoringNotchWindow.swift",
            "boringNotch/components/Notch/BoringNotchSkyLightWindow.swift",
        ):
            window_source = (ROOT / relative_path).read_text(encoding="utf-8")
            self.assertIn("allowsShelfKeyboardFocus", window_source)
            self.assertIn("func makeShelfItemFirstResponder", window_source)
            self.assertIn("override func resignKey()", window_source)

    def test_space_opens_quick_look_for_selected_files(self):
        self.assertIn("event.keyCode == 49", SHELF_ITEM_VIEW)
        self.assertIn("onQuickLook?()", SHELF_ITEM_VIEW)
        self.assertIn("showQuickLookForSelection", SHELF_ITEM_VIEW)
        self.assertIn("quickLookService.show(urls: urls, selectFirst: true)", SHELF_ITEM_VIEW)

    def test_shortcut_preserves_modified_space_commands(self):
        self.assertIn(
            "let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]",
            SHELF_ITEM_VIEW,
        )


if __name__ == "__main__":
    unittest.main()
