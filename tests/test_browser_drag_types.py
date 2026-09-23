from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class BrowserDragTypesTests(unittest.TestCase):
    def test_chrome_image_types_and_unsupported_payload(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = str(Path(folder) / 'drag-types')
            result = subprocess.run(['xcrun', 'swiftc', str(ROOT / 'boringNotch/observers/DragDetector.swift'), str(ROOT / 'tests/BrowserDragTypesHarness.swift'), '-o', executable], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('BrowserDragTypesHarness: PASS', result.stdout)
