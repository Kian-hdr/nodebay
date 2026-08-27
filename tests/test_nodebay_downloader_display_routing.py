from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DOWNLOADER = (ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift").read_text()
DROP = (ROOT / "boringNotch/components/Shelf/Services/ShelfDropService.swift").read_text()
DRAG = (ROOT / "boringNotch/observers/DragDetector.swift").read_text()
APP = (ROOT / "boringNotch/boringNotchApp.swift").read_text()
SHELF = (ROOT / "boringNotch/components/Shelf/Views/ShelfView.swift").read_text()
XPC = (ROOT / "BoringNotchXPCHelper/BoringNotchXPCHelper.swift").read_text()
CASK = (ROOT / "Casks/nodebay.rb").read_text()


class NodebayDownloaderDisplayRoutingTests(unittest.TestCase):
    def test_all_entry_points_use_shared_download_coordinator(self):
        self.assertIn("final class DownloadCoordinator", DOWNLOADER)
        self.assertIn("downloadCoordinator.add(urls: urls)", SHELF)
        self.assertIn("DownloadCoordinator.shared.add(urls: urls)", APP)

    def test_url_parser_rejects_credentials_and_deduplicates(self):
        self.assertIn("components.user == nil", DOWNLOADER)
        self.assertIn("components.password == nil", DOWNLOADER)
        self.assertIn("seen.insert($0.absoluteString).inserted", DOWNLOADER)
        self.assertIn("internetShortcutURL", DROP)

    def test_output_is_staged_and_collision_safe(self):
        self.assertIn('".nodebay-download-', DOWNLOADER)
        self.assertIn("collisionSafeURL", DOWNLOADER)
        self.assertIn('appending(path: "Nodebay"', DOWNLOADER)
        self.assertNotIn("/bin/sh", DOWNLOADER)

    def test_format_quality_and_progress_are_applied(self):
        self.assertIn("maximumVideoHeight", DOWNLOADER)
        self.assertIn("audioBitrate", DOWNLOADER)
        self.assertIn('"--progress-template"', DOWNLOADER)
        self.assertIn("ApprovedProcessProgressParser", XPC)

    def test_drag_types_accept_extra_representations(self):
        self.assertIn("item.types.contains", DRAG)
        self.assertNotIn("item.types.allSatisfy", DRAG)

    def test_display_routing_uses_uuid_and_dynamic_window_frame(self):
        self.assertIn("NotchDragRoutingCoordinator", DRAG)
        self.assertIn("displayUUID: uuid", APP)
        self.assertIn("frame.midX", APP)
        self.assertNotIn("screen == windowScreen", APP)

    def test_hover_paste_is_narrow_and_passes_unhandled_events(self):
        self.assertIn("NotchPasteShortcutMonitor", DRAG)
        self.assertIn("monitor.shouldHandle?() == true", DRAG)
        self.assertIn("return Unmanaged.passUnretained(event)", DRAG)
        self.assertIn("return nil", DRAG)

    def test_homebrew_installs_separate_companion_formulas(self):
        self.assertIn('depends_on formula: "yt-dlp"', CASK)
        self.assertIn('depends_on formula: "ffmpeg"', CASK)

    def test_add_link_popover_holds_notch_open_for_its_full_lifecycle(self):
        self.assertIn("beginAddLinkInteractionIfNeeded()", SHELF)
        self.assertIn("endAddLinkInteractionIfNeeded()", SHELF)
        self.assertIn("SharingStateManager.shared.beginInteraction()", SHELF)
        self.assertIn("SharingStateManager.shared.endInteraction()", SHELF)
        self.assertIn(".onChange(of: showsAddLink)", SHELF)
        self.assertIn(".onDisappear", SHELF)


if __name__ == "__main__":
    unittest.main()
