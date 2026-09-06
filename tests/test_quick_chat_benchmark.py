"""Offline regression checks; these tests never submit model requests."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from quick_chat_benchmark_cases import quality_check
from benchmark_quick_chat import summarize


class QuickChatBenchmarkTests(unittest.TestCase):
    def test_short_cases(self):
        self.assertTrue(quality_check("arithmetic", "17 × 24 = 408."))
        self.assertFalse(quality_check("arithmetic", "1408"))
        self.assertTrue(quality_check("format", "- Copy\n- Open\n- Retain"))
        self.assertFalse(quality_check("format", "- Copy\n- Open"))

    def test_summary_retains_uncertainty(self):
        answer = "- 18 of 20 checks passed.\n- Hardware blocks two; September 15 proposed.\n- EUR 2400 budget, EUR 600 spent."
        self.assertTrue(quality_check("summary", answer))
        self.assertFalse(quality_check("summary", answer.replace("proposed", "confirmed")))

    def test_code_is_not_executed_and_empty_list_is_preserved(self):
        answer = "```python\ndef add(value, items=None):\n    if items is None:\n        items = []\n    items.append(value)\n    return items\n```"
        self.assertTrue(quality_check("code", answer))
        self.assertFalse(quality_check("code", answer.replace("items is None", "not items")))

    def test_long_requested_length_and_structure(self):
        answer = "# Restore\n" + "restore " * 80 + "\n# Version\n" + "version " * 80 + "\n# Offline\n" + "offline deletion " * 40
        self.assertTrue(quality_check("long", answer))
        self.assertFalse(quality_check("long", "# Restore\nversion offline deletion"))

    def test_tail_summary_labels_backend_not_ui(self):
        report = summarize([{"startup": .09, "first_answer": n, "completion": n + .1}
                            for n in (2, 4, 6)])
        self.assertEqual(report["metrics"]["first_answer"]["median"], 4)
        self.assertEqual(report["metrics"]["first_answer"]["p95_nearest_rank"], 6)
        self.assertTrue(report["small_sample_tail_warning"])
        self.assertIn("not signed-app", report["measurement_surface"])
        self.assertIsNone(summarize([])["metrics"]["first_answer"])


if __name__ == "__main__":
    unittest.main()
