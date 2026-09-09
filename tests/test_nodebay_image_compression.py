"""Production Swift image-copy regression tests; generated fixtures and stub optimizer."""
import hashlib
import json
import os
import pathlib
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVICE = ROOT / "boringNotch/components/Shelf/Services/ImageOptimCompressionService.swift"
IMAGEOPTIM = pathlib.Path("/Applications/ImageOptim.app/Contents/MacOS/ImageOptim")


def png_bytes(*, padding=False, color=b"\x00\x80\xff"):
    """Generate a complete 2x2 RGB PNG, optionally with removable text metadata."""
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))

    raw = (b"\x00" + color * 2) * 2
    chunks = [chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))]
    if padding:
        chunks.append(chunk(b"tEXt", b"Comment\x00" + b"fixture metadata " * 256))
    chunks.extend([chunk(b"IDAT", zlib.compress(raw)), chunk(b"IEND", b"")])
    return b"\x89PNG\r\n\x1a\n" + b"".join(chunks)


class ImageCompressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if sys.platform != "darwin" or not shutil.which("swiftc"):
            raise unittest.SkipTest("Requires macOS Swift and ImageIO")
        if not os.access(IMAGEOPTIM, os.X_OK):
            raise unittest.SkipTest("Production availability check requires ImageOptim in /Applications; it is never launched")
        cls.temp = tempfile.TemporaryDirectory(prefix="nodebay-image-tests-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = pathlib.Path(cls.temp.name)
        cls.harness = cls.root / "harness"
        subprocess.run([
            "swiftc", str(ROOT / "tests/ImageCompressionHarness.swift"), str(SERVICE),
            str(ROOT / "boringNotch/extensions/URL+SecurityScoped.swift"),
            "-o", str(cls.harness),
        ], check=True, capture_output=True, text=True)

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.case.cleanup)
        self.case_root = pathlib.Path(self.case.name)
        self.source_folder = self.case_root / "source-folder"
        self.source_folder.mkdir()
        self.source = self.source_folder / "fixture.png"
        self.source.write_bytes(png_bytes(padding=True))
        self.optimized = self.case_root / "optimized-fixture.png"
        self.optimized.write_bytes(png_bytes())
        self.outputs = self.case_root / "results"

    def run_service(self, mode="compress", source=None, suffix="optimized"):
        run = subprocess.run([
            str(self.harness), mode, str(source or self.source), str(self.outputs),
            suffix, str(self.optimized),
        ], capture_output=True, text=True, timeout=15, check=True)
        return json.loads(run.stdout.strip().splitlines()[-1])

    def assert_no_outputs(self):
        self.assertEqual(list(self.outputs.rglob("*")) if self.outputs.exists() else [], [])

    def test_read_only_source_parent_uses_owned_output_and_preserves_original(self):
        original = self.source.read_bytes()
        before = hashlib.sha256(original).hexdigest()
        self.source_folder.chmod(0o555)
        self.addCleanup(self.source_folder.chmod, 0o755)
        self.assertFalse(os.access(self.source_folder, os.W_OK), "Fixture parent must reject writes")

        result = self.run_service()
        self.assertIn("output", result)
        output = pathlib.Path(result["output"])
        self.assertEqual(output.parent, self.outputs)
        self.assertEqual(result["source"], str(self.source))
        self.assertEqual(result["optimizerArguments"], [str(output)])
        self.assertEqual(result["copiedSize"], len(original))
        self.assertEqual(result["original"], len(original))
        self.assertEqual(result["compressed"], output.stat().st_size)
        self.assertEqual(output.read_bytes(), self.optimized.read_bytes())
        self.assertTrue(result["smaller"])
        self.assertEqual(result["saved"], len(original) - output.stat().st_size)
        self.assertEqual(hashlib.sha256(self.source.read_bytes()).hexdigest(), before)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertEqual(list(self.source_folder.iterdir()), [self.source])

    def test_repeated_names_keep_distinct_outputs_and_earlier_bytes(self):
        first = self.run_service()
        self.assertIn("output", first)
        first_path = pathlib.Path(first["output"])
        first_bytes = first_path.read_bytes()
        self.optimized.write_bytes(png_bytes(color=b"\xff\x40\x00"))
        second = self.run_service()
        self.assertIn("output", second)
        second_path = pathlib.Path(second["output"])
        self.assertNotEqual(first_path, second_path)
        self.assertEqual(first_path.read_bytes(), first_bytes)
        self.assertEqual(second_path.read_bytes(), self.optimized.read_bytes())
        self.assertEqual(first_path.parent, self.outputs)
        self.assertEqual(second_path.parent, self.outputs)

    def test_read_only_source_becomes_writable_copy_without_changing_source_mode(self):
        original = self.source.read_bytes()
        self.source.chmod(0o444)
        result = self.run_service()
        self.assertIn("output", result)
        output = pathlib.Path(result["output"])
        self.assertEqual(output.read_bytes(), self.optimized.read_bytes())
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(self.source.stat().st_mode), 0o444)

    def test_symlink_source_copies_bytes_without_changing_target_or_permissions(self):
        original = self.source.read_bytes()
        self.source.chmod(0o444)
        link = self.source_folder / "linked-image.png"
        link.symlink_to(self.source.name)
        result = self.run_service(source=link)
        self.assertIn("output", result)
        output = pathlib.Path(result["output"])
        self.assertFalse(output.is_symlink())
        self.assertEqual(output.parent, self.outputs)
        self.assertEqual(output.read_bytes(), self.optimized.read_bytes())
        self.assertEqual(result["source"], str(link))
        self.assertEqual(self.source.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(self.source.stat().st_mode), 0o444)
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.readlink(), pathlib.Path(self.source.name))

    def test_missing_and_unsupported_inputs_never_reach_optimizer(self):
        unsupported = self.source_folder / "unsupported.txt"
        unsupported.write_text("fixture")
        for source, expected in [
            (self.source_folder / "missing.png", "no longer available"),
            (unsupported, "not supported"),
        ]:
            with self.subTest(source=source.name):
                result = self.run_service(source=source)
                self.assertIn(expected, result.get("error", ""))
                self.assertEqual(result["optimizerArguments"], [])
                self.assert_no_outputs()

    def test_optimizer_failure_throw_and_invalid_result_remove_only_copy(self):
        original = self.source.read_bytes()
        for mode in ["failure", "throws", "invalid"]:
            with self.subTest(mode=mode):
                result = self.run_service(mode=mode)
                self.assertIn("error", result)
                self.assertEqual(len(result["optimizerArguments"]), 1)
                self.assertEqual(self.source.read_bytes(), original)
                self.assert_no_outputs()

    def test_cancellation_before_and_during_optimization_cleans_copy(self):
        original = self.source.read_bytes()
        for mode in ["cancel-before", "cancel-during"]:
            with self.subTest(mode=mode):
                result = self.run_service(mode=mode)
                self.assertEqual(result.get("error"), "cancelled", result)
                self.assertEqual(len(result["optimizerArguments"]), 0 if mode == "cancel-before" else 1)
                self.assertEqual(self.source.read_bytes(), original)
                self.assert_no_outputs()

    def test_suffix_cannot_escape_output_folder(self):
        for suffix in ["../../escape:part / other", " \n\t "]:
            with self.subTest(suffix=suffix):
                result = self.run_service(suffix=suffix)
                self.assertIn("output", result)
                output = pathlib.Path(result["output"])
                self.assertEqual(output.parent, self.outputs)
                self.assertNotIn(":", output.name)
                self.assertTrue(output.is_file())

    def test_no_reduction_is_reported_without_losing_original(self):
        original = self.source.read_bytes()
        self.optimized.write_bytes(original)
        result = self.run_service()
        self.assertIn("output", result)
        self.assertFalse(result["smaller"])
        self.assertEqual(result["saved"], 0)
        self.assertEqual(result["percentage"], 0)
        self.assertEqual(self.source.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
