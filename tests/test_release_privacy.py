import pathlib
import plistlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleasePrivacyTests(unittest.TestCase):
    def test_upstream_update_feed_is_absent(self):
        with (ROOT / "boringNotch" / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
        self.assertEqual(info["SUFeedURL"], "$(NODEBAY_UPDATE_FEED_URL)")
        self.assertEqual(info["SUPublicEDKey"], "$(NODEBAY_UPDATE_PUBLIC_ED_KEY)")
        self.assertFalse(info.get("SUEnableAutomaticChecks", True))
        self.assertTrue(info["SURequireSignedFeed"])
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
        self.assertEqual(info["SUSignedFeedFailureExpirationInterval"], 0)
        self.assertFalse(info["SUEnableSystemProfiling"])

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
