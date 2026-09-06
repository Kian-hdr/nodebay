from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuickChatCoreTests(unittest.TestCase):
    def test_provider_choice_is_opt_in_and_api_key_is_not_stored_in_defaults(self):
        core = (ROOT / "boringNotch/QuickChatCore.swift").read_text()
        coordinator = (ROOT / "boringNotch/QuickChatCoordinator.swift").read_text()
        settings = (ROOT / "boringNotch/QuickChatView.swift").read_text()
        tabs = (ROOT / "boringNotch/components/Tabs/TabSelectionView.swift").read_text()
        self.assertIn('return .off', core)
        self.assertIn('case codexCLI = "codex-cli"', core)
        self.assertIn('case openAIAPI = "openai-api"', core)
        self.assertIn('kSecClassGenericPassword', coordinator)
        self.assertNotIn('defaults.set(normalized', coordinator)
        self.assertIn('URLSessionConfiguration.ephemeral', coordinator)
        self.assertIn('"store": false', coordinator)
        self.assertIn('Validate Connection', settings)
        self.assertIn('chat.enabled', tabs)

    def test_openai_provider_request_and_validation_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-chat-api-") as folder:
            executable = str(Path(folder) / "test")
            sources = ["boringNotch/QuickChatCore.swift", "boringNotch/QuickChatKnowledge.swift",
                       "boringNotch/QuickChatCoordinator.swift",
                       "boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift",
                       "tests/QuickChatAPIHarness.swift"]
            result = subprocess.run(["swiftc", *[str(ROOT / name) for name in sources], "-o", executable],
                                    capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_native_transcript_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-chat-transcript-") as folder:
            executable = str(Path(folder) / "test")
            sources = ["boringNotch/QuickChatCore.swift", "boringNotch/QuickChatComposer.swift",
                       "boringNotch/QuickChatTranscript.swift", "tests/QuickChatTranscriptHarness.swift"]
            result = subprocess.run(["swiftc", *[str(ROOT / name) for name in sources], "-o", executable],
                                    capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_coordinator_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-chat-coordinator-") as folder:
            executable = str(Path(folder) / "test")
            sources = ["boringNotch/QuickChatCore.swift", "boringNotch/QuickChatKnowledge.swift",
                       "boringNotch/QuickChatCoordinator.swift",
                       "boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift",
                       "tests/QuickChatCoordinatorHarness.swift"]
            result = subprocess.run(["swiftc", *[str(ROOT / name) for name in sources], "-o", executable],
                                    capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_header_has_one_top_anchored_content_budget(self):
        content = (ROOT / "boringNotch/ContentView.swift").read_text()
        self.assertIn("vm.notchSize.height : nil, alignment: .top", content)
        self.assertIn(".frame(height: tabHeight, alignment: .top)", content)
        self.assertNotIn(".frame(height: 150)", (ROOT / "boringNotch/QuickChatView.swift").read_text())

    def test_worker_event_and_reasoning_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-chat-worker-") as folder:
            executable = str(Path(folder) / "test")
            result = subprocess.run(["swiftc", str(ROOT / "BoringNotchXPCHelper/QuickChatWorker.swift"),
                            str(ROOT / "tests/QuickChatWorkerHarness.swift"), "-o", executable],
                           capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_ephemeral_chat_does_not_rebuild_provider_database(self):
        worker = (ROOT / "BoringNotchXPCHelper/QuickChatWorker.swift").read_text()
        self.assertNotIn("sqlite_home=", worker)
        for protection in ('"--ephemeral"', 'history.persistence=\\"none\\"',
                           '"--ignore-user-config"', '"--ignore-rules"',
                           '"--strict-config"', 'deny process-exec'):
            self.assertIn(protection, worker)

    def test_native_composer_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-composer-") as folder:
            executable = str(Path(folder) / "test")
            result = subprocess.run(["swiftc", str(ROOT / "boringNotch/QuickChatComposer.swift"),
                            str(ROOT / "tests/QuickChatComposerHarness.swift"), "-o", executable],
                           capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_knowledge_fixture_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-knowledge-core-") as folder:
            executable = str(Path(folder) / "test")
            result = subprocess.run(["swiftc", str(ROOT / "boringNotch/QuickChatCore.swift"),
                            str(ROOT / "boringNotch/QuickChatKnowledge.swift"),
                            str(ROOT / "tests/QuickChatKnowledgeHarness.swift"), "-o", executable],
                           capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            subprocess.run([executable], check=True, capture_output=True, timeout=15)

    def test_executable_domain_contract(self):
        with tempfile.TemporaryDirectory(prefix="nodebay-chat-core-") as folder:
            executable = str(Path(folder) / "test")
            subprocess.run(["swiftc", str(ROOT / "boringNotch/QuickChatCore.swift"),
                            str(ROOT / "tests/QuickChatCoreHarness.swift"), "-o", executable],
                           check=True, capture_output=True, timeout=90)
            subprocess.run([executable], check=True, capture_output=True, timeout=15)
