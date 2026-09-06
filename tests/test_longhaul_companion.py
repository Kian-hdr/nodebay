"""Non-disruptive companion protocol tests. No apps, service or power changes."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class LonghaulCompanionTests(unittest.TestCase):
    def test_automatic_control_acknowledgement(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-longhaul-toggle-") as temporary:
            binary = pathlib.Path(temporary) / "automatic-control-harness"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-o", str(binary),
                str(ROOT / "boringNotch/Longhaul/LonghaulCompanionModels.swift"),
                str(ROOT / "boringNotch/Longhaul/LonghaulCompanionClient.swift"),
                str(ROOT / "boringNotch/Longhaul/LonghaulCompanionViews.swift"),
                str(ROOT / "BoringNotchXPCHelper/BoringNotchXPCHelperProtocol.swift"),
                str(ROOT / "tests/LonghaulAutomaticControlHarness.swift"),
            ], check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn("checks passed; no apps launched", result.stdout)

    def test_hidden_control_is_removed_from_the_parent_stack(self):
        header = (ROOT / "boringNotch/components/Notch/BoringHeader.swift").read_text()
        self.assertRegex(header, r"if longhaul\.showsNotchControl\s*\{\s*LonghaulNotchButton\(\)\s*\}")
        settings = (ROOT / "boringNotch/Longhaul/LonghaulCompanionViews.swift").read_text().split("struct LonghaulNotchButton", 1)[0]
        self.assertIn('Button("Open Longhaul")', settings)
        self.assertIn('Button("Connect to Longhaul")', settings)
        self.assertIn('Button("Check Connection")', settings)

    def test_protocol_and_worker_classification(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-longhaul-test-") as temporary:
            binary = pathlib.Path(temporary) / "companion-harness"
            subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-o", str(binary),
                str(ROOT / "boringNotch/Longhaul/LonghaulCompanionModels.swift"),
                str(ROOT / "BoringNotchXPCHelper/LonghaulRelay.swift"),
                str(ROOT / "tests/LonghaulCompanionHarness.swift"),
            ], check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=20)
            self.assertIn("checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
