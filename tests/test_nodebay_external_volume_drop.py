import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
LOAD_HELPERS = ROOT / "boringNotch/extensions/NSItemProvider+LoadHelpers.swift"
DROP_SERVICE = ROOT / "boringNotch/components/Shelf/Services/ShelfDropService.swift"


class ExternalVolumeDropContractTests(unittest.TestCase):
    def test_bookmark_is_captured_inside_item_provider_callback(self):
        source = LOAD_HELPERS.read_text()
        callback = source.index("loadItem(forTypeIdentifier: typeIdentifier")
        bookmark = source.index("let bookmark = try Bookmark(url: url)", callback)
        resume = source.index("continuation.resume", bookmark)
        self.assertLess(callback, bookmark)
        self.assertLess(bookmark, resume)
        self.assertIn("startAccessingSecurityScopedResource()", source[callback:resume])

    def test_external_file_uses_captured_bookmark_without_recreating_it(self):
        source = DROP_SERVICE.read_text()
        self.assertIn("extractDroppedFileReference()", source)
        self.assertIn(".file(bookmark: droppedFile.bookmarkData)", source)

        branch_start = source.index("if let droppedFile = await provider.extractDroppedFileReference()")
        branch_end = source.index("if let url = await provider.extractURL()", branch_start)
        self.assertNotIn("createBookmark(for:", source[branch_start:branch_end])

    def test_plain_external_volume_paths_are_parsed_as_file_urls_first(self):
        source = LOAD_HELPERS.read_text()
        parser_start = source.index("private static func fileURL(fromProviderString")
        parser = source[parser_start:]
        absolute_path = parser.index('if value.hasPrefix("/")')
        generic_url = parser.index("URL(string: value)")
        self.assertLess(absolute_path, generic_url)


if __name__ == "__main__":
    unittest.main()
