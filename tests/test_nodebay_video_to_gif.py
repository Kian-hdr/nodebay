import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "boringNotch" / "components" / "Shelf" / "Services" / "ShelfActionService.swift").read_text()
VIEW_MODEL = (ROOT / "boringNotch" / "components" / "Shelf" / "ViewModels" / "ShelfItemViewModel.swift").read_text()


class VideoToGIFContractTests(unittest.TestCase):
    def test_conversion_is_bounded_and_duration_is_checked_first(self):
        self.assertIn("maximumFrameCount = 180", SERVICE)
        self.assertIn("framesPerSecond = 12", SERVICE)
        duration_check = SERVICE.index("guard duration <= Self.maximumDuration")
        ffmpeg_lookup = SERVICE.index("firstAvailableApprovedExecutable(", duration_check)
        self.assertLess(duration_check, ffmpeg_lookup)
        self.assertIn("case keptOriginalVideo", SERVICE)

    def test_original_video_is_preserved_and_long_video_falls_back(self):
        self.assertNotIn("replaceItemAt", SERVICE)
        self.assertNotIn("moveItem(at: inputURL", SERVICE)
        self.assertIn("copyItem(at: accessibleURL, to: localInputURL)", SERVICE)
        self.assertIn("removeItem(at: inputDirectory)", SERVICE)
        self.assertIn('alert.messageText = "Kept as Video"', VIEW_MODEL)
        self.assertIn("the original video remains on the shelf instead", VIEW_MODEL)

    def test_gif_result_is_persistent_and_collision_safe(self):
        self.assertIn("NodebayManagedFileStorage.uniqueOutputURL", SERVICE)
        self.assertIn("for: .media", SERVICE)
        self.assertIn('"-n"', SERVICE)
        self.assertIn("isTemporary: false", VIEW_MODEL)

    def test_ffmpeg_pipeline_and_output_validation_are_bounded(self):
        self.assertIn('engine: "ffmpeg"', SERVICE)
        self.assertIn("palettegen=max_colors=256", SERVICE)
        self.assertIn("paletteuse=dither=sierra2_4a", SERVICE)
        self.assertIn("timeout: .seconds(120)", SERVICE)
        self.assertIn("maximumLogBytes: 32_768", SERVICE)
        self.assertIn("CGImageSourceGetCount", SERVICE)
        self.assertIn("frameCount > 1, frameCount <= maximumFrameCount", SERVICE)

    def test_context_menu_exposes_video_action(self):
        self.assertIn('NSMenuItem(title: "Video Actions"', VIEW_MODEL)
        self.assertIn('NSMenuItem(title: "Create GIF"', VIEW_MODEL)
        self.assertIn('case "Create GIF":', VIEW_MODEL)


if __name__ == "__main__":
    unittest.main()
