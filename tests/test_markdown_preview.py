"""Quick Look packaging/privacy contracts plus the real reusable renderer tests."""
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MarkdownPreviewTests(unittest.TestCase):
    def test_native_renderer(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-markdown-tests-") as scratch:
            result = subprocess.run([
                "swift", "test", "--package-path", str(ROOT / "Packages/NodebayMarkdown"),
                "--scratch-path", scratch,
            ], capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Executed 8 tests", result.stdout + result.stderr)

    def test_extension_registration_and_sandbox(self):
        info = plistlib.loads((ROOT / "NodebayMarkdownPreview/Info.plist").read_bytes())
        ext = info["NSExtension"]
        self.assertEqual(ext["NSExtensionPointIdentifier"], "com.apple.quicklook.preview")
        self.assertEqual(ext["NSExtensionAttributes"]["QLSupportedContentTypes"], ["net.daringfireball.markdown"])
        entitlements = plistlib.loads((ROOT / "NodebayMarkdownPreview/NodebayMarkdownPreview.entitlements").read_bytes())
        self.assertEqual(entitlements, {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.files.user-selected.read-only": True,
        })
        app = plistlib.loads((ROOT / "boringNotch/Info.plist").read_bytes())
        markdown = next(t for t in app["UTImportedTypeDeclarations"] if t.get("UTTypeIdentifier") == "net.daringfireball.markdown")
        self.assertEqual(markdown["UTTypeTagSpecification"]["public.filename-extension"], ["md", "markdown"])

    def test_no_webview_network_logging_or_window_chrome(self):
        controller = (ROOT / "NodebayMarkdownPreview/PreviewViewController.swift").read_text()
        renderer = (ROOT / "Packages/NodebayMarkdown/Sources/NodebayMarkdown/MarkdownRenderer.swift").read_text()
        for forbidden in ("URLSession", "WKWebView", "NSWindow(", "NSLog(", "print(", "CGEvent", "NSWorkspace.shared.open"):
            self.assertNotIn(forbidden, controller + renderer)
        # User-approved contract: expose the host material, without adding a surface.
        for forbidden in ("NSVisualEffectView", "backgroundColor =", "wantsLayer", "cornerRadius", "NSBox("):
            self.assertNotIn(forbidden, controller)
        self.assertIn("scroll.drawsBackground = false", controller)
        self.assertIn("textView.drawsBackground = false", controller)
        self.assertIn("worker.async", controller)
        self.assertIn("self.generation == request", controller)
        self.assertIn("isEditable = false", controller)
        self.assertIn("isSelectable = true", controller)
        self.assertIn("allowsExtendedAttributes: false", renderer)


if __name__ == "__main__":
    unittest.main()
