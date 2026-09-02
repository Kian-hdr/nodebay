import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
STORAGE = ROOT / "boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift"
ENTITLEMENTS = ROOT / "boringNotch/boringNotch.entitlements"
CONVERTER = ROOT / "boringNotch/components/Shelf/Services/ShelfActionService.swift"
VIEW_MODEL = ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift"
SHELF_STATE = ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift"


class ManagedFileStorageContractTests(unittest.TestCase):
    def test_broad_downloads_entitlement_is_not_required_for_file_drops(self):
        self.assertNotIn(
            "com.apple.security.files.downloads.read-write",
            ENTITLEMENTS.read_text(),
        )

    def test_markdown_results_use_collision_safe_managed_storage(self):
        storage = STORAGE.read_text()
        converter = CONVERTER.read_text()
        self.assertIn('case markdown = "Generated/Markdown"', storage)
        self.assertIn("UUID().uuidString", storage)
        self.assertIn("NodebayManagedFileStorage.uniqueOutputURL", converter)

    def test_markdown_shelf_items_are_not_file_promises(self):
        source = VIEW_MODEL.read_text()
        for occurrence in source.split("MarkItDownConversionService.shared.convert")[1:]:
            nearby = occurrence[:500]
            if "ShelfItem(kind: .file" in nearby:
                self.assertIn("isTemporary: false", nearby)

    def test_existing_temporary_markdown_is_migrated_without_deleting_source(self):
        storage = STORAGE.read_text()
        state = SHELF_STATE.read_text()
        self.assertIn("persistentMarkdownCopy", state)
        self.assertIn("migrateLegacyTemporaryMarkdown", state)
        self.assertIn("normalizeLegacyPDFGlyphPlaceholders", storage)
        self.assertIn(r"\\(cid:\\d+\\)", storage)
        migration = state[state.index("private static func migrateLegacyTemporaryMarkdown") :]
        self.assertNotIn("removeItem", migration)
        self.assertIn("copyItem", storage)

    def test_downloader_defaults_to_nodebay_managed_storage(self):
        service = (
            ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift"
        ).read_text()
        self.assertIn("NodebayManagedFileStorage.directory(for: .downloads)", service)


if __name__ == "__main__":
    unittest.main()
