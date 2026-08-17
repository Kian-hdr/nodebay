import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = (ROOT / "BoringNotchXPCHelper" / "BoringNotchXPCHelper.swift").read_text()
DOWNLOADER = (ROOT / "boringNotch" / "components" / "Shelf" / "Services" / "MediaDownloaderService.swift").read_text()
CONVERTER = (ROOT / "boringNotch" / "components" / "Shelf" / "Services" / "ShelfActionService.swift").read_text()
IMAGEOPTIM = (ROOT / "boringNotch" / "components" / "Shelf" / "Services" / "ImageOptimCompressionService.swift").read_text()


class XPCEngineIsolationTests(unittest.TestCase):
    def test_helper_is_allowlisted_and_never_invokes_a_shell(self):
        self.assertIn('case "markitdown"', HELPER)
        self.assertIn('case "yt-dlp"', HELPER)
        self.assertIn('case "imageoptim"', HELPER)
        self.assertIn('case "ffmpeg"', HELPER)
        self.assertNotIn('/bin/sh', HELPER)
        self.assertNotIn('/bin/zsh', HELPER)
        self.assertIn('arguments.count <= 256', HELPER)
        self.assertIn('maximumLogBytes', HELPER)
        self.assertIn('cancelApprovedProcess', HELPER)

    def test_all_processing_services_use_the_xpc_path(self):
        self.assertIn('runApproved(\n            engine: "yt-dlp"', DOWNLOADER)
        self.assertIn('runApproved(\n            engine: "markitdown"', CONVERTER)
        self.assertIn('runApproved(\n                engine: "imageoptim"', IMAGEOPTIM)


if __name__ == "__main__":
    unittest.main()
