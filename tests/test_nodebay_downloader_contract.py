import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift"


class DownloaderSecurityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")

    def test_rejects_non_http_schemes_and_url_credentials(self):
        self.assertIn('["http", "https"].contains', self.source)
        self.assertIn("components.user == nil", self.source)
        self.assertIn("components.password == nil", self.source)

    def test_disables_config_plugins_and_browser_cookies(self):
        for option in (
            '"--ignore-config"',
            '"--no-config-locations"',
            '"--no-plugin-dirs"',
            '"--no-cookies-from-browser"',
        ):
            self.assertIn(option, self.source)

    def test_uses_structured_process_arguments_and_safe_output_checks(self):
        self.assertNotIn("/bin/sh", self.source)
        self.assertIn("SafeProcessRunner.run", self.source)
        self.assertIn('"--restrict-filenames"', self.source)
        self.assertIn("MediaDownloaderError.unsafeOutput", self.source)
        self.assertIn("collisionSafeURL", self.source)

    def test_homebrew_detection_is_delegated_outside_the_app_sandbox(self):
        registry = (
            ROOT / "boringNotch/Providers/ProcessingProviderRegistry.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("for executable in candidateURLs", registry)
        self.assertIn("firstAvailableApprovedExecutable", self.source)

    def test_dropped_links_download_into_the_persistent_shelf(self):
        shelf_state = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift"
        ).read_text(encoding="utf-8")
        item_view_model = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift"
        ).read_text(encoding="utf-8")
        settings = (
            ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("droppedMediaLinks", shelf_state)
        self.assertIn("downloadMediaAndWait()", shelf_state)
        self.assertIn("replaceReference(item, with: [completedItem])", item_view_model)
        self.assertIn('LabeledContent("Completed downloads", value: "Always added to Nodebay")', settings)
        self.assertNotIn('nodebay.downloader.addResults', settings)

    def test_compressed_copy_is_inserted_beside_its_source(self):
        item_view_model = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift"
        ).read_text(encoding="utf-8")
        settings = (
            ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("insertResult(outputItem, beside: item)", item_view_model)
        self.assertIn('LabeledContent("Completed results", value: "Always added to Nodebay")', settings)
        self.assertNotIn('nodebay.imageOptim.addResults', settings)

    def test_dropped_links_download_into_the_persistent_shelf(self):
        shelf_state = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfStateViewModel.swift"
        ).read_text(encoding="utf-8")
        item_view_model = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift"
        ).read_text(encoding="utf-8")
        settings = (
            ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("droppedMediaLinks", shelf_state)
        self.assertIn("downloadMediaAndWait()", shelf_state)
        self.assertIn("replaceReference(item, with: [completedItem])", item_view_model)
        self.assertIn('LabeledContent("Completed downloads", value: "Always added to Nodebay")', settings)
        self.assertNotIn('nodebay.downloader.addResults', settings)

    def test_compressed_copy_is_inserted_beside_its_source(self):
        item_view_model = (
            ROOT / "boringNotch/components/Shelf/ViewModels/ShelfItemViewModel.swift"
        ).read_text(encoding="utf-8")
        settings = (
            ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("insertResult(outputItem, beside: item)", item_view_model)
        self.assertIn('LabeledContent("Completed results", value: "Always added to Nodebay")', settings)
        self.assertNotIn('nodebay.imageOptim.addResults', settings)


if __name__ == "__main__":
    unittest.main()
