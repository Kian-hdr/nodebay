"""Exercise the release guard with actual compatible and incompatible Mach-O files."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("runtime_compatibility", ROOT / "scripts/verify_runtime_compatibility.py")
compatibility = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compatibility)


class DeploymentMetadataTests(unittest.TestCase):
    def test_modern_and_legacy_metadata_ignore_sdk_versions(self):
        self.assertEqual(compatibility.minimum_versions("""
Load command 8
      cmd LC_VERSION_MIN_MACOSX
  version 10.13
      sdk 26.5
Load command 9
      cmd LC_BUILD_VERSION
 platform 1
    minos 11.0
      sdk 26.5
"""), ["10.13", "11.0"])

    def test_semantic_versions_do_not_compare_lexically(self):
        self.assertLess(compatibility.version_tuple("9.9"), compatibility.version_tuple("15.0"))
        self.assertEqual(compatibility.version_tuple("15"), compatibility.version_tuple("15.0.0"))


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("clang"), "Requires the macOS compiler and Mach-O tools")
class BinaryCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="nodebay-deployment-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "fixture.c"
        self.source.write_text("int nodebay_fixture(void) { return 0; }\n")

    def library(self, minimum="15.0", architecture="arm64", identifier="@rpath/libfixture.dylib"):
        target = self.root / "libfixture.dylib"
        subprocess.run([
            "clang", "-arch", architecture, f"-mmacosx-version-min={minimum}",
            "-dynamiclib", str(self.source), f"-Wl,-install_name,{identifier}", "-o", str(target),
        ], check=True, capture_output=True, text=True)
        return target

    def test_accepts_floor_15_even_when_built_with_newer_sdk(self):
        self.library()
        count, errors = compatibility.verify(self.root, "15.0", "arm64")
        self.assertEqual(count, 1)
        self.assertEqual(errors, [])

    def test_rejects_runtime_built_only_for_macos_26(self):
        self.library(minimum="26.0")
        _, errors = compatibility.verify(self.root, "15.0", "arm64")
        self.assertTrue(any("requires macOS 26.0" in error for error in errors), errors)

    def test_rejects_installed_homebrew_library_dependency(self):
        self.library(identifier="/opt/homebrew/lib/libfixture.dylib")
        _, errors = compatibility.verify(self.root, "15.0", "arm64")
        self.assertTrue(any("external dependency" in error for error in errors), errors)

    def test_rejects_intel_only_library(self):
        self.library(architecture="x86_64")
        _, errors = compatibility.verify(self.root, "15.0", "arm64")
        self.assertTrue(any("missing arm64" in error for error in errors), errors)

    def test_empty_or_nonbinary_directory_is_not_a_success(self):
        count, errors = compatibility.verify(self.root, "15.0", "arm64")
        self.assertEqual(count, 0)
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
