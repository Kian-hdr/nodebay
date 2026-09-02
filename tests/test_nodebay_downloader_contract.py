from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift").read_text()


class DownloaderSecurityContractTests(unittest.TestCase):
    def test_current_ytdlp_runtime_and_actionable_youtube_403_recovery(self):
        self.assertIn('static let pinnedTestedVersion = "2026.8.19"', SOURCE)
        self.assertIn('message.localizedCaseInsensitiveContains("HTTP Error 403")', SOURCE)
        self.assertIn('case .youtubeRequestRejected:', SOURCE)
        self.assertIn('brew upgrade yt-dlp', SOURCE)
        self.assertIn('does not access browser cookies automatically', SOURCE)

    def test_rejects_non_http_schemes_and_url_credentials(self):
        self.assertIn('["http", "https"].contains', SOURCE)
        self.assertIn("components.user == nil", SOURCE)
        self.assertIn("components.password == nil", SOURCE)

    def test_disables_config_plugins_and_browser_cookies(self):
        for option in ('"--ignore-config"', '"--no-config-locations"', '"--no-plugin-dirs"', '"--no-cookies-from-browser"'):
            self.assertIn(option, SOURCE)

    def test_uses_xpc_structured_arguments_and_safe_output(self):
        self.assertNotIn("/bin/sh", SOURCE)
        self.assertIn("SafeProcessRunner.runApproved", SOURCE)
        self.assertIn('"--restrict-filenames"', SOURCE)
        self.assertIn("MediaDownloaderError.unsafeOutput", SOURCE)
        self.assertIn("collisionSafeURL", SOURCE)

    def test_canonicalizes_sandbox_downloads_symlink_before_containment_check(self):
        self.assertIn("requestedDestination.resolvingSymlinksInPath().standardizedFileURL", SOURCE)
        self.assertIn("let canonicalStaging = staging.resolvingSymlinksInPath().standardizedFileURL", SOURCE)
        self.assertIn("let filename = generatedURL.lastPathComponent", SOURCE)
        self.assertIn("canonicalStaging.appending(path: filename).standardizedFileURL", SOURCE)
        self.assertIn("canonicalGenerated.deletingLastPathComponent().path == canonicalStaging.path", SOURCE)
        self.assertIn("values.isRegularFile == true", SOURCE)
        self.assertIn("values.isSymbolicLink != true", SOURCE)
        self.assertNotIn('standardizedFileURL.path.hasPrefix(staging.path + "/")', SOURCE)

    def test_default_download_directory_is_app_owned_and_errors_are_visible(self):
        entitlements = (ROOT / "boringNotch/boringNotch.entitlements").read_text()
        self.assertNotIn("com.apple.security.files.downloads.read-write", entitlements)
        self.assertIn("NodebayManagedFileStorage.directory(for: .downloads)", SOURCE)
        self.assertIn("presentFailure(error)", SOURCE)
        self.assertIn('alert.messageText = "Download Failed"', SOURCE)
        self.assertIn("SharingStateManager.shared.beginInteraction()", SOURCE)

    def test_dropped_links_use_one_persistent_coordinator(self):
        shelf_state = (ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift").read_text()
        settings = (ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift").read_text()
        self.assertIn("DownloadCoordinator.shared.start(items: droppedMediaLinks)", shelf_state)
        self.assertIn("shelf.replaceReference(item, with: [completed])", SOURCE)
        self.assertIn('LabeledContent("Completed downloads", value: "Always added to Nodebay")', settings)

    def test_compressed_copy_remains_beside_source(self):
        item_view_model = (ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift").read_text()
        self.assertIn("insertResult(outputItem, beside: item)", item_view_model)


if __name__ == "__main__":
    unittest.main()
