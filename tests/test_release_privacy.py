import pathlib
import plistlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleasePrivacyTests(unittest.TestCase):
    def test_upstream_update_feed_is_absent(self):
        with (ROOT / "boringNotch" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        self.assertFalse(info.get("SUEnableAutomaticChecks", True))

    def test_transport_security_is_not_globally_disabled(self):
        with (ROOT / "boringNotch" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        ats = info.get("NSAppTransportSecurity", {})
        self.assertNotIn("NSAllowsArbitraryLoads", ats)
        self.assertTrue(ats.get("NSAllowsLocalNetworking"))

    def test_privacy_manifest_declares_no_tracking_or_collection(self):
        with (ROOT / "boringNotch" / "PrivacyInfo.xcprivacy").open("rb") as handle:
            privacy = plistlib.load(handle)
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])
        self.assertEqual(privacy["NSPrivacyTrackingDomains"], [])


if __name__ == "__main__":
    unittest.main()
