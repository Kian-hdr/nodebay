from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NodebayBrandingTests(unittest.TestCase):
    def test_operational_public_urls_use_nodebay_repository(self) -> None:
        operational_files = [
            "README.md",
            "CONTRIBUTING.md",
            "SECURITY.md",
            "SUPPORT.md",
            "Casks/nodebay.rb",
            "Casks/nodebay.rb.template",
            "scripts/package_homebrew_arm64.sh",
            "boringNotch/extensions/BundleInfos.swift",
            "boringNotch/components/Settings/Views/AboutView.swift",
            "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift",
        ]
        for relative_path in operational_files:
            content = (ROOT / relative_path).read_text(encoding="utf-8")
            self.assertNotIn(
                "Kian-hdr/boring.notch",
                content,
                f"stale owned-repository URL in {relative_path}",
            )
            self.assertNotIn(
                "blob/feature/nodebay",
                content,
                f"stale implementation-branch URL in {relative_path}",
            )

    def test_inherited_publish_destinations_are_absent(self) -> None:
        workflows = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((ROOT / ".github/workflows").glob("*.yml"))
        )
        forbidden = [
            "TheBoredTeam/homebrew-boring-notch",
            "CROWDIN_PERSONAL_TOKEN",
            "CROWDIN_PROJECT_ID",
            "PRIVATE_SPARKLE_KEY",
            "HOMEBREW_TAP_TOKEN",
            "https://github.com/TheBoredTeam/boring.notch/releases/download",
        ]
        for value in forbidden:
            self.assertNotIn(value, workflows)

    def test_required_community_files_exist(self) -> None:
        required = [
            "CODE_OF_CONDUCT.md",
            "CONTRIBUTING.md",
            "PRIVACY.md",
            "SECURITY.md",
            "SUPPORT.md",
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/RELEASE_CHECKLIST.md",
            ".github/ISSUE_TEMPLATE/bug-report.yml",
            ".github/ISSUE_TEMPLATE/feature-request.yml",
        ]
        for relative_path in required:
            self.assertTrue((ROOT / relative_path).is_file(), relative_path)

    def test_unpublished_build_has_no_sparkle_feed(self) -> None:
        info_plist = (ROOT / "boringNotch/Info.plist").read_text(encoding="utf-8")
        self.assertNotIn("SUFeedURL", info_plist)
        self.assertIn("SUEnableAutomaticChecks", info_plist)

    def test_release_workflow_is_manual_and_confirmation_gated(self) -> None:
        workflow = (ROOT / ".github/workflows/nodebay-release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("workflow_dispatch", workflow)
        self.assertIn("inputs.confirmation == 'RELEASE'", workflow)
        self.assertNotIn("issue_comment", workflow)

    def test_media_controller_default_does_not_reenter_music_manager(self) -> None:
        constants = (ROOT / "boringNotch/models/Constants.swift").read_text(
            encoding="utf-8"
        )
        declaration = next(
            line for line in constants.splitlines() if "static let mediaController =" in line
        )
        self.assertIn("default: .nowPlaying", declaration)
        self.assertNotIn("MusicManager.shared", declaration)

    def test_native_settings_command_is_available(self) -> None:
        app_source = (ROOT / "boringNotch/boringNotchApp.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("CommandGroup(replacing: .appSettings)", app_source)
        self.assertIn('Button("Settings…")', app_source)


if __name__ == "__main__":
    unittest.main()
