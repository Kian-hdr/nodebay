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
        self.assertEqual(manifest["version"], "0.1.0")
        self.assertIn('extensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"', bridge)
        self.assertIn('browserBridgeExtensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"', helper)
        self.assertIn('nativeHostName = "com.nodebay.browser_bridge"', bridge)

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
            hello = {"type": "hello", "extensionVersion": "0.1.0"}
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
