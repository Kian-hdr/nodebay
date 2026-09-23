import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class BrowserImageDropTests(unittest.TestCase):
    def test_real_providers_prefer_images_persist_valid_bytes_and_preserve_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = pathlib.Path(temporary) / "browser-image-drop"
            sources = [
                "boringNotch/extensions/URL+SecurityScoped.swift",
                "boringNotch/components/Shelf/Models/Bookmark.swift",
                "boringNotch/extensions/NSItemProvider+LoadHelpers.swift",
                "boringNotch/components/Shelf/Services/TemporaryFileStorageService.swift",
                "boringNotch/components/Shelf/Services/ShelfDropService.swift",
                "tests/ShelfDroppedImageProviderHarness.swift",
            ]
            result = subprocess.run(["xcrun", "swiftc", "-parse-as-library", *[str(ROOT / x) for x in sources], "-o", str(executable)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("ShelfDroppedImageProviderHarness: PASS", result.stdout)
