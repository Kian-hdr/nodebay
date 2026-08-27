import json
import os
import socket
import struct
import subprocess
import threading
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXTENSION = ROOT / "BrowserBridge/extension"
NATIVE_HOST = ROOT / "BrowserBridge/native/nodebay-browser-bridge"


def native_frame(payload: dict) -> bytes:
    data = json.dumps(payload, separators=(",", ":")).encode()
    return struct.pack("<I", len(data)) + data


def read_exact(stream, count: int) -> bytes:
    result = b""
    while len(result) < count:
        chunk = stream.read(count - len(result))
        if not chunk:
            raise EOFError("native host closed before a complete frame arrived")
        result += chunk
    return result


class BrowserBridgeContractTests(unittest.TestCase):
    def test_extension_permissions_are_limited_to_supported_media_sites(self):
        manifest = json.loads((EXTENSION / "manifest.json").read_text())
        self.assertEqual(manifest["permissions"], ["nativeMessaging"])
        self.assertEqual(
            set(manifest["host_permissions"]),
            {"https://www.youtube.com/*", "https://music.youtube.com/*"},
        )
        serialized = json.dumps(manifest)
        self.assertNotIn("<all_urls>", serialized)
        self.assertNotIn('"cookies"', serialized)
        self.assertNotIn('"history"', serialized)
        self.assertNotIn('"tabs"', serialized)

    def test_extension_and_app_share_the_pinned_identity(self):
        manifest = json.loads((EXTENSION / "manifest.json").read_text())
        bridge = (ROOT / "boringNotch/managers/BrowserMediaBridge.swift").read_text()
        helper = (ROOT / "BoringNotchXPCHelper/BoringNotchXPCHelper.swift").read_text()
        self.assertEqual(manifest["version"], "0.1.1")
        self.assertIn('extensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"', bridge)
        self.assertIn('browserBridgeExtensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"', helper)
        self.assertIn('nativeHostName = "com.nodebay.browser_bridge"', bridge)

    def test_downloadable_tab_url_is_forwarded_without_broad_browser_permissions(self):
        background = (EXTENSION / "background.js").read_text()
        bridge = (ROOT / "boringNotch/managers/BrowserMediaBridge.swift").read_text()
        manager = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
        home = (ROOT / "boringNotch/components/Notch/NotchHomeView.swift").read_text()
        self.assertIn("pageURL: sender.tab.url", background)
        self.assertIn("let pageURL: URL?", bridge)
        self.assertIn("activeDownloadableURL", manager)
        self.assertIn("resolveChromeYouTubeURL", manager)
        self.assertIn("resolveYouTubeSearchURL", manager)
        self.assertIn("downloadableYouTubeMediaURL", manager)
        self.assertIn("matches.count == 1", manager)
        self.assertIn("canDownloadActiveMedia", manager)
        self.assertIn("Download current media to Nodebay", home)
        self.assertIn('Image(systemName: "arrow.down.circle")', home)
        self.assertIn(".frame(width: 30, height: 30)", home)
        self.assertIn(".overlay(alignment: .trailing)", home)
        self.assertNotIn('Text(musicManager.isResolvingCurrentMediaDownload', home)
        self.assertIn("downloadActiveMediaToNodebay", home)
        self.assertIn("DownloadCoordinator.shared.add", manager)

    def test_now_playing_search_fallback_is_bounded_and_cookie_free(self):
        downloader = (ROOT / "boringNotch/components/Shelf/Services/MediaDownloaderService.swift").read_text()
        manager = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
        self.assertIn('"ytsearch5:\\(query)"', downloader)
        self.assertIn("titleTokens.isSubset(of: candidateTokens)", downloader)
        self.assertIn("artistTokens.isDisjoint", downloader)
        self.assertIn('"--no-cookies-from-browser"', downloader)
        self.assertIn("case .noYouTubeTab, .noMatchingYouTubeTab:", manager)
        self.assertIn('url.path == "/watch"', manager)
        self.assertNotIn('url.path == "/"', manager)
        self.assertNotIn("if candidates.count == 1", manager)

    def test_chrome_automation_permission_has_recovery_path(self):
        entitlements = (ROOT / "boringNotch/boringNotch.entitlements").read_text()
        music = (ROOT / "boringNotch/managers/MusicManager.swift").read_text()
        helper = (ROOT / "boringNotch/helpers/AppleScriptHelper.swift").read_text()

        self.assertIn("com.google.Chrome", entitlements)
        self.assertIn("code: errorNumber", helper)
        self.assertIn("userInfo[NSLocalizedDescriptionKey] = errorMessage", helper)
        self.assertIn("nsError.code == -1743", music)
        self.assertIn("Privacy_Automation", music)

    def test_extension_exposes_no_arbitrary_command_channel(self):
        background = (EXTENSION / "background.js").read_text()
        content = (EXTENSION / "media.js").read_text()
        for forbidden in ("eval(", "new Function", "child_process", "executeScript"):
            self.assertNotIn(forbidden, background)
            self.assertNotIn(forbidden, content)
        self.assertIn('const allowedActions = new Set(["play", "pause", "togglePlay", "seek", "setVolume", "next", "previous"]);', background)

    def test_native_host_round_trip_uses_chrome_framing_and_loopback(self):
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        received = []
        command = {"type": "command", "tabId": 42, "action": "pause"}

        def server():
            connection, _ = listener.accept()
            with connection:
                stream = connection.makefile("rwb", buffering=0)
                received.append(json.loads(stream.readline()))
                received.append(json.loads(stream.readline()))
                stream.write(json.dumps(command, separators=(",", ":")).encode() + b"\n")

        thread = threading.Thread(target=server, daemon=True)
        thread.start()
        environment = os.environ.copy()
        environment["NODEBAY_BROWSER_BRIDGE_TEST"] = "1"
        environment["NODEBAY_BROWSER_BRIDGE_PORT"] = str(port)
        process = subprocess.Popen(
            [str(NATIVE_HOST)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
        )
        try:
            hello = {"type": "hello", "extensionVersion": "0.1.1"}
            process.stdin.write(native_frame(hello))
            process.stdin.flush()

            length = struct.unpack("<I", read_exact(process.stdout, 4))[0]
            reply = json.loads(read_exact(process.stdout, length))
            self.assertEqual(reply, command)
            thread.join(timeout=2)
            self.assertFalse(thread.is_alive())
            self.assertEqual(received[0]["type"], "nativeHostConnected")
            self.assertEqual(received[1], hello)
        finally:
            process.terminate()
            process.wait(timeout=2)
            process.stdin.close()
            process.stdout.close()
            process.stderr.close()
            listener.close()


if __name__ == "__main__":
    unittest.main()
