import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class NodebayNoticeTests(unittest.TestCase):
    def test_every_locked_swift_package_has_an_exact_notice_entry(self):
        resolved = json.loads((ROOT / "boringNotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
        manifest = json.loads((ROOT / "third_party/nodebay-components.json").read_text())
        pins = {item["identity"]: item["state"] for item in resolved["pins"]}
        entries = {item["id"]: item for item in manifest["components"]}
        self.assertEqual(set(pins), set(entries))
        for identity, state in pins.items():
            self.assertEqual(state.get("version"), entries[identity]["version"])
            self.assertEqual(state.get("revision"), entries[identity]["revision"])

        companions = {item["id"]: item for item in manifest["companions"]}
        self.assertEqual({"yt-dlp", "ffmpeg", "imageoptim"}, set(companions))
        self.assertTrue(all(item["bundled"] is False for item in companions.values()))

    def test_all_processing_integrations_are_declared_in_notices(self):
        notices = (ROOT / "THIRD_PARTY_NOTICES_NODEBAY.md").read_text(encoding="utf-8")
        for name in ("Boring Notch", "MarkItDown", "yt-dlp", "FFmpeg", "ImageOptim", "MediaRemoteAdapter"):
            self.assertIn(name, notices)


if __name__ == "__main__":
    unittest.main()
