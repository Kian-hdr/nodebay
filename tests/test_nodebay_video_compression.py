"""Real Swift service/FFmpeg integration, using generated media, never user files."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVICE = ROOT / "boringNotch/components/Shelf/Services/VideoCompressionService.swift"


class VideoCompressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ffmpeg = shutil.which("ffmpeg")
        cls.ffprobe = shutil.which("ffprobe")
        if not cls.ffmpeg or not cls.ffprobe or not shutil.which("swiftc"):
            raise unittest.SkipTest("Requires macOS Swift, FFmpeg and ffprobe")
        cls.temp = tempfile.TemporaryDirectory(prefix="nodebay-video-tests-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = pathlib.Path(cls.temp.name)
        cls.harness = cls.root / "harness"
        subprocess.run(["swiftc", str(ROOT / "tests/VideoCompressionHarness.swift"), str(SERVICE),
                        str(ROOT / "boringNotch/extensions/URL+SecurityScoped.swift"),
                        "-o", str(cls.harness)], check=True, capture_output=True, text=True)
        cls.source = cls.root / "source.mp4"
        subprocess.run([cls.ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
                        "testsrc2=size=640x360:rate=24:duration=2", "-f", "lavfi", "-i",
                        "sine=frequency=440:duration=2", "-c:v", "libx264", "-preset", "ultrafast",
                        "-crf", "0", "-c:a", "aac", "-shortest", str(cls.source)], check=True)

    def setUp(self):
        self.case = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.case.cleanup)
        self.case_root = pathlib.Path(self.case.name)
        self.outputs = self.case_root / "results"
        self.work = self.case_root / "work"
        self.work.mkdir()

    def run_service(self, mode="compress", source=None):
        run = subprocess.run([str(self.harness), mode, self.ffmpeg, str(source or self.source),
                              str(self.outputs), str(self.work)], capture_output=True, text=True, timeout=45, check=True)
        return json.loads(run.stdout.strip().splitlines()[-1])

    def probe(self, path):
        return json.loads(subprocess.check_output([self.ffprobe, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)]))

    def test_mp4_is_smaller_playable_and_original_unchanged(self):
        before = hashlib.sha256(self.source.read_bytes()).hexdigest()
        result = self.run_service()
        self.assertTrue(result["smaller"], result)
        streams = self.probe(result["output"])["streams"]
        self.assertEqual({s["codec_name"] for s in streams}, {"h264", "aac"})
        video = next(s for s in streams if s["codec_type"] == "video")
        self.assertEqual((video["width"], video["height"]), (640, 360))
        subprocess.run([self.ffmpeg, "-v", "error", "-xerror", "-i", result["output"], "-f", "null", "-"], check=True)
        self.assertEqual(before, hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.assertEqual(list(self.work.iterdir()), [])

    def test_repeated_names_get_separate_retained_files(self):
        a, b = self.run_service(), self.run_service()
        self.assertNotEqual(a["output"], b["output"])
        self.assertTrue(pathlib.Path(a["output"]).is_file())
        self.assertTrue(pathlib.Path(b["output"]).is_file())

    def test_audio_optional_and_portrait_not_upscaled(self):
        source = self.case_root / "portrait.MP4"
        subprocess.run([self.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=180x320:rate=12:duration=1",
                        "-c:v", "libx264", str(source)], check=True)
        result = self.run_service(source=source)
        streams = self.probe(result["output"])["streams"]
        self.assertEqual(len(streams), 1)
        self.assertEqual((streams[0]["width"], streams[0]["height"]), (180, 320))

    def test_invalid_and_unsupported_inputs_leave_no_output(self):
        for name in ["broken.mp4", "unsupported.txt"]:
            source = self.case_root / name
            source.write_text("not media")
            self.assertIn("error", self.run_service(source=source))
            self.assertEqual(list(self.work.iterdir()), [])
            self.assertFalse(self.outputs.exists())

    def test_missing_engine_failure_and_cancellation_cleanup(self):
        for mode in ["unavailable", "failure", "cancel-before", "cancel-during"]:
            result = self.run_service(mode=mode)
            self.assertIn("error", result)
            self.assertNotIn("private sentinel", result["error"])
            self.assertEqual(list(self.work.iterdir()), [])
            self.assertFalse(self.outputs.exists())

    def test_unusual_filename_is_not_a_shell_command(self):
        source = self.case_root / "hello; echo injected $(whoami).MP4"
        shutil.copyfile(self.source, source)
        self.assertIn("output", self.run_service(source=source))
        self.assertTrue(source.is_file())

    def test_only_one_encode_runs_at_a_time(self):
        self.assertIn("Another video", self.run_service(mode="busy")["error"])
        self.assertEqual(list(self.work.iterdir()), [])

    def test_no_size_reduction_is_reported_honestly(self):
        source = self.case_root / "tiny.mp4"
        subprocess.run([self.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=size=64x64:rate=1:duration=5",
                        "-c:v", "libx264", "-preset", "veryslow", "-crf", "51", str(source)], check=True)
        result = self.run_service(source=source)
        self.assertFalse(result["smaller"], result)
        self.assertGreaterEqual(result["compressed"], result["original"])

    def test_hdr_is_rejected_without_changing_source(self):
        source = self.case_root / "hdr.mp4"
        subprocess.run([self.ffmpeg, "-v", "error", "-f", "lavfi", "-i", "color=size=64x64:duration=1",
                        "-c:v", "libx265", "-x265-params", "log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
                        "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1", str(source)], check=True)
        before = source.read_bytes()
        self.assertIn("HDR", self.run_service(source=source)["error"])
        self.assertEqual(before, source.read_bytes())
        self.assertEqual(list(self.work.iterdir()), [])

    def test_local_only_arguments_and_no_overwrite(self):
        existing = self.outputs
        existing.write_bytes(b"keep this output")
        args = self.run_service(mode="arguments")
        self.assertEqual(args[args.index("-protocol_whitelist") + 1], "file")
        self.assertIn("-n", args)
        self.assertNotIn("-y", args)
        run = subprocess.run([self.ffmpeg] + args, capture_output=True, timeout=10)
        # FFmpeg versions differ in the exit status for a -n skip. The safety
        # contract is that the existing output remains byte-for-byte intact.
        self.assertEqual(existing.read_bytes(), b"keep this output")


if __name__ == "__main__":
    unittest.main()
