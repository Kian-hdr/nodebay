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
            self.assertIn("Executed 16 tests", result.stdout + result.stderr)

    def test_extension_registration_and_sandbox(self):
        info = plistlib.loads((ROOT / "NodebayMarkdownPreview/Info.plist").read_bytes())
        ext = info["NSExtension"]
        self.assertEqual(ext["NSExtensionPointIdentifier"], "com.apple.quicklook.preview")
        self.assertEqual(ext["NSExtensionAttributes"]["QLSupportedContentTypes"], ["net.daringfireball.markdown"])
        entitlements = plistlib.loads((ROOT / "NodebayMarkdownPreview/NodebayMarkdownPreview.entitlements").read_bytes())
        self.assertEqual(entitlements, {
            "com.apple.security.app-sandbox": True,
            "com.apple.security.files.user-selected.read-only": True,
            "com.apple.security.network.client": True,
            "com.apple.security.application-groups": ["$(DEVELOPMENT_TEAM).Nodebay.MarkdownPreview"],
        })
        app = plistlib.loads((ROOT / "boringNotch/Info.plist").read_bytes())
        app_entitlements = plistlib.loads((ROOT / "boringNotch/boringNotch.entitlements").read_bytes())
        group = "$(DEVELOPMENT_TEAM).Nodebay.MarkdownPreview"
        self.assertEqual(app_entitlements["com.apple.security.application-groups"], [group])
        self.assertEqual(app["NodebayPreviewAppGroup"], group)
        self.assertEqual(info["NodebayPreviewAppGroup"], group)
        markdown = next(t for t in app["UTImportedTypeDeclarations"] if t.get("UTTypeIdentifier") == "net.daringfireball.markdown")
        self.assertEqual(markdown["UTTypeTagSpecification"]["public.filename-extension"], ["md", "markdown"])

    def test_no_webview_network_logging_or_window_chrome(self):
        controller = (ROOT / "NodebayMarkdownPreview/PreviewViewController.swift").read_text()
        renderer = (ROOT / "Packages/NodebayMarkdown/Sources/NodebayMarkdown/MarkdownRenderer.swift").read_text()
        for forbidden in ("URLSession", "WKWebView", "NSWindow(", "NSLog(", "print(", "CGEvent", "NSWorkspace.shared.open"):
            self.assertNotIn(forbidden, controller + renderer)
        # Quick Look owns window materials and chrome. The optional document
        # background is native scroll-view backing, not an added material/card.
        for forbidden in ("NSVisualEffectView(", "wantsLayer", "cornerRadius", "NSBox("):
            self.assertNotIn(forbidden, controller)
        self.assertIn("view = scroll", controller)
        self.assertIn("scroll.drawsBackground = false", controller)
        self.assertIn("textView.drawsBackground = false", controller)
        self.assertIn("worker.async", controller)
        self.assertIn("self.generation == request", controller)
        self.assertIn("isEditable = false", controller)
        self.assertIn("isSelectable = true", controller)
        self.assertIn("allowsExtendedAttributes: false", renderer)

    def test_background_preference_in_real_controller(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-preview-background-") as scratch:
            scratch = pathlib.Path(scratch)
            sources = sorted((ROOT / "Packages/NodebayMarkdown/Sources/NodebayMarkdown").glob("*.swift"))
            module = subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-emit-library", "-emit-module",
                "-module-name", "NodebayMarkdown", *map(str, sources),
                "-emit-module-path", str(scratch / "NodebayMarkdown.swiftmodule"),
                "-o", str(scratch / "libNodebayMarkdown.dylib"),
            ], capture_output=True, text=True, timeout=180)
            self.assertEqual(module.returncode, 0, module.stdout + module.stderr)
            executable = scratch / "background-tests"
            compiled = subprocess.run([
                "xcrun", "swiftc", "-swift-version", "5", "-I", str(scratch),
                "-L", str(scratch), "-lNodebayMarkdown", "-Xlinker", "-rpath",
                "-Xlinker", str(scratch),
                str(ROOT / "NodebayMarkdownPreview/PreviewViewController.swift"),
                str(ROOT / "NodebayMarkdownPreview/MarkdownDiagramPresenter.swift"),
                str(ROOT / "NodebayMarkdownPreview/MermaidDiagramRenderer.swift"),
                str(ROOT / "tests/MarkdownPreviewBackgroundHarness.swift"),
                "-o", str(executable),
            ], capture_output=True, text=True, timeout=180)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Markdown preview background checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
