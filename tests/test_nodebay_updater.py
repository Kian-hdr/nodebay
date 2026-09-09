import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class NodebayUpdaterTests(unittest.TestCase):
    """Runs production decision code, without pretending to install an update."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.executable = pathlib.Path(cls.directory.name) / "updater-policy"
        subprocess.run(
            ["swiftc", "-swift-version", "5", "-strict-concurrency=targeted",
             str(ROOT / "boringNotch/components/Settings/NodebayUpdatePolicy.swift"),
             str(ROOT / "tests/NodebayUpdatePolicyHarness.swift"),
             "-o", str(cls.executable)],
            check=True, capture_output=True, text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_case(self, case):
        result = subprocess.run([str(self.executable), case], timeout=20,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Updater policy checks passed", result.stdout)

    def test_legacy_preferences_require_choice_without_overwriting_opt_out(self):
        self.run_case("migration")

    def test_only_complete_signed_nodebay_channels_are_accepted(self):
        self.run_case("configuration")

    def test_manual_check_is_available_before_automatic_consent(self):
        self.run_case("check-requests")

    def test_busy_update_resumes_once_after_persistence_flush(self):
        self.run_case("defer-install")

    def test_new_job_blocks_final_termination_after_deferral_resumes(self):
        self.run_case("termination-race")

    def test_aborted_update_drops_continuation_and_allows_retry(self):
        self.run_case("cancel-install")


if __name__ == "__main__":
    unittest.main()
