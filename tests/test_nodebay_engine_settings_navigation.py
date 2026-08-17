import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "boringNotch/components/Settings/SettingsView.swift").read_text(
    encoding="utf-8"
)
ENGINES = (
    ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"
).read_text(encoding="utf-8")


class EngineSettingsNavigationContractTests(unittest.TestCase):
    def test_sidebar_has_one_processing_settings_destination(self):
        self.assertIn('case .plugins: "Plugins & Engines"', SETTINGS)
        self.assertNotIn("case converters", SETTINGS)
        self.assertNotIn("case imageCompressor", SETTINGS)
        self.assertNotIn('case .converters: "Converters"', SETTINGS)
        self.assertNotIn('case .imageCompressor: "Image Compressor"', SETTINGS)

    def test_engine_settings_separate_overview_documents_and_images(self):
        self.assertIn('case overview = "Overview"', ENGINES)
        self.assertIn('case documents = "Documents"', ENGINES)
        self.assertIn('case images = "Images"', ENGINES)
        self.assertIn(".pickerStyle(.segmented)", ENGINES)
        self.assertIn("MarkItDownConfigurationSections()", ENGINES)
        self.assertIn("ImageCompressionConfigurationSections()", ENGINES)

    def test_downloader_remains_a_distinct_workflow(self):
        self.assertIn('case .downloader: "Downloader"', SETTINGS)
        self.assertIn("DownloaderSettingsView()", SETTINGS)


if __name__ == "__main__":
    unittest.main()
