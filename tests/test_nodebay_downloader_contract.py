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


if __name__ == "__main__":
    unittest.main()
