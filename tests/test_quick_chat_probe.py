"""The preparatory probe must not turn partial evidence into chat readiness."""
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "quick_chat_probe", ROOT / "scripts/probe_quick_chat_provider.py"
)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class QuickChatProbeTests(unittest.TestCase):
    def test_inherited_servers_remain_detectable(self):
        report = probe.summarize_status({"mcp_servers": {
            "synthetic_a": {}, "synthetic_b": {"enabled": False},
            "synthetic_c": {"enabled": True},
        }}, {})
        self.assertEqual(report["mcp_entries_after_empty_override"], 3)
        self.assertEqual(report["enabled_mcp_entries_after_empty_override"], 2)

    def test_missing_feature_does_not_count_as_disabled(self):
        self.assertFalse(probe.summarize_status({}, {})["requested_features_disabled"])

    def test_empty_servers_and_disabled_features_are_not_certification(self):
        report = probe.summarize_status({
            "features": {key: False for key in probe.DISABLED}, "mcp_servers": {},
        }, {"account": {"type": "chatgpt"}})
        self.assertTrue(report["requested_features_disabled"])
        self.assertEqual(report["security_compatibility"], "not established")
        self.assertFalse(report["thread_started"])
        self.assertFalse(report["model_request_sent"])

    def test_raw_config_and_account_are_never_in_diagnostics(self):
        report = json.dumps(probe.summarize_status({
            "developer_instructions": "PRIVATE SYNTHETIC PROMPT",
            "mcp_servers": {"PRIVATE SERVER": {"env": {"TOKEN": "SYNTHETIC TOKEN"}}},
        }, {"account": {"email": "private@example.invalid"}}))
        for marker in ("PRIVATE", "SYNTHETIC", "TOKEN", "private@example.invalid"):
            self.assertNotIn(marker, report)

    def test_signed_out_is_not_authorized(self):
        report = probe.summarize_status({}, {"account": None})
        self.assertFalse(report["account_present_not_freshly_validated"])


if __name__ == "__main__":
    unittest.main()
