import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SHELF_ITEM_VIEW = (
    ROOT / "boringNotch/components/Shelf/Views/ShelfItemView.swift"
).read_text(encoding="utf-8")


class ShelfTileBoundsContractTests(unittest.TestCase):
    def test_selection_surface_is_inset_inside_shelf_panel(self):
        self.assertIn(
            "private let selectionBackgroundVerticalInset: CGFloat = 6",
            SHELF_ITEM_VIEW,
        )
        self.assertIn(
            ".padding(.vertical, selectionBackgroundVerticalInset)",
            SHELF_ITEM_VIEW,
        )

    def test_file_and_action_content_sizes_remain_readable(self):
        self.assertIn(".frame(width: 56, height: 56)", SHELF_ITEM_VIEW)
        self.assertIn(".frame(height: 30, alignment: .top)", SHELF_ITEM_VIEW)
        self.assertIn(".frame(height: 20)", SHELF_ITEM_VIEW)

    def test_remove_control_is_inset_from_selection_border(self):
        self.assertIn(
            "private let removalControlOffset = CGSize(width: 42, height: -50)",
            SHELF_ITEM_VIEW,
        )
        self.assertNotIn(".offset(x: 48, y: -56)", SHELF_ITEM_VIEW)


if __name__ == "__main__":
    unittest.main()
