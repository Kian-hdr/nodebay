"""Measure the actual reusable SwiftUI music layout, without running media providers."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def swift_struct(text, name):
    start = text.index("struct " + name + "<")
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


class MusicPlayerLayoutTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "requires macOS SwiftUI")
    def test_native_row_geometry(self):
        text = (ROOT / "boringNotch/components/Notch/NotchHomeView.swift").read_text()
        column = swift_struct(text, "MusicPlayerColumn")
        strip = swift_struct(text, "MusicControlStrip")
        with tempfile.TemporaryDirectory(prefix="nodebay-player-layout-") as directory:
            root = Path(directory)
            source = root / "Column.swift"
            legacy_strip = strip.replace("struct MusicControlStrip<", "struct LegacyMusicControlStrip<", 1)
            legacy_strip = legacy_strip.replace(".scrollIndicators(.never)", ".scrollIndicators(.hidden)")
            source.write_text("import SwiftUI\n" + column + "\n" + strip + "\n" + legacy_strip)
            executable = root / "layout"
            subprocess.run(["swiftc", str(source), str(ROOT / "boringNotch/components/HoverButton.swift"),
                            str(ROOT / "tests/MusicPlayerLayoutHarness.swift"), "-o", str(executable)],
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn("PASS: 6 native SwiftUI layout cases", result.stdout)
            self.assertIn("PASS: 4 native control-strip cases", result.stdout)
            # Reproduce the former flexible-reader layout with the original 190pt notch budget.
            before = subprocess.run([str(executable), "--legacy"], capture_output=True, text=True, timeout=20)
            self.assertNotEqual(before.returncode, 0)
            self.assertIn("Timeline overlaps playback icons", before.stderr)
            scrollers_before = subprocess.run([str(executable), "--legacy-scrollers"],
                                              capture_output=True, text=True, timeout=20)
            self.assertNotEqual(scrollers_before.returncode, 0)
            self.assertIn("Horizontal scroller reduced the 40pt playback viewport", scrollers_before.stderr)

if __name__ == "__main__":
    unittest.main()
