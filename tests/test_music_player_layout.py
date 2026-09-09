"""Measure the actual reusable SwiftUI music layout, without running media providers."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class MusicPlayerLayoutTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "requires macOS SwiftUI")
    def test_native_row_geometry(self):
        text = (ROOT / "boringNotch/components/Notch/NotchHomeView.swift").read_text()
        column = text[text.index("struct MusicPlayerColumn<"):text.index("struct AlbumArtView:")]
        with tempfile.TemporaryDirectory(prefix="nodebay-player-layout-") as directory:
            root = Path(directory)
            source = root / "Column.swift"
            source.write_text("import SwiftUI\n" + column)
            executable = root / "layout"
            subprocess.run(["swiftc", str(source), str(ROOT / "tests/MusicPlayerLayoutHarness.swift"), "-o", str(executable)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("PASS: 6 native SwiftUI layout cases", result.stdout)
            # Reproduce the former flexible-reader layout with the original 190pt notch budget.
            before = subprocess.run([str(executable), "--legacy"], capture_output=True, text=True)
            self.assertNotEqual(before.returncode, 0)
            self.assertIn("Timeline overlaps playback icons", before.stderr)

if __name__ == "__main__":
    unittest.main()
