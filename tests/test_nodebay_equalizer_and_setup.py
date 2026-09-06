import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
EXTENSION = ROOT / "BrowserBridge/extension"
CORE = ROOT / "boringNotch/managers/NodebayEqualizerCore.swift"
MANAGER = ROOT / "boringNotch/managers/NodebayEqualizer.swift"
BRIDGE = ROOT / "boringNotch/managers/BrowserMediaBridge.swift"
MUSIC = ROOT / "boringNotch/managers/MusicManager.swift"
HELPER = ROOT / "BoringNotchXPCHelper/BoringNotchXPCHelper.swift"
REGISTRY = ROOT / "boringNotch/Providers/ProcessingProviderRegistry.swift"
SETTINGS = ROOT / "boringNotch/components/Settings/Views/PluginsEnginesSettingsView.swift"


class EqualizerAndSetupTests(unittest.TestCase):
    def test_equalizer_popover_uses_interactive_three_tone_curve(self):
        source = (ROOT / "boringNotch/components/Notch/NotchHomeView.swift").read_text()
        popover = source.split("private struct EqualizerPopover", 1)[1].split(
            "private struct MediaSourcePicker", 1
        )[0]
        self.assertIn('Text("Equalizer")', popover)
        self.assertIn('Toggle("Equalizer"', popover)
        self.assertIn("EqualizerCurveEditor(", popover)
        self.assertNotIn('toneButton(', popover)
        self.assertNotIn('LazyVGrid', popover)
        self.assertIn("DragGesture(minimumDistance: 0", popover)
        self.assertIn("@FocusState private var focusedToneIndex: Int?", popover)
        self.assertIn("focusedToneIndex = nil", popover)
        self.assertIn("accessibilityAdjustableAction", popover)
        self.assertIn("accessibilityReduceMotion", popover)
        self.assertIn("NodebayEqualizerCurveScale.normalizedY", popover)
        self.assertIn("NodebayEqualizerCurveScale.gain(atNormalizedY:", popover)
        self.assertIn("row == 3", popover)
        self.assertNotIn("frequencyLabel", popover)

        manager = MANAGER.read_text()
        tone_setter = manager.split("func setToneGain", 1)[1].split("private func", 1)[0]
        self.assertIn("baseProfile.setting(clamped, for: tone).gains", tone_setter)
        self.assertIn("guard abs(baseProfile.gain(for: tone) - clamped) >= 0.5", tone_setter)

    def test_equalizer_profile_harness(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = pathlib.Path(directory) / "equalizer-harness"
            subprocess.run(
                ["swiftc", str(CORE), str(ROOT / "tests/NodebayEqualizerHarness.swift"), "-o", str(executable)],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("checks passed", result.stdout)

    def test_av_audio_unit_equalizer_changes_the_audio_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = pathlib.Path(directory) / "av-equalizer-harness"
            subprocess.run(
                [
                    "swiftc",
                    str(ROOT / "tests/NodebayAVAudioEqualizerHarness.swift"),
                    "-o",
                    str(executable),
                    "-framework",
                    "AVFoundation",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            result = subprocess.run([str(executable)], check=True, capture_output=True, text=True)
            self.assertIn("AVAudioUnitEQ signal check passed", result.stdout)

    def test_local_audio_path_uses_real_av_audio_engine(self):
        source = MANAGER.read_text()
        self.assertIn("AVAudioEngine()", source)
        self.assertIn("AVAudioUnitEQ", source)
        self.assertIn("scheduleGeneration", source)
        self.assertIn("pausedFrame = currentFrame\n        scheduleGeneration += 1", source)
        self.assertIn("startAccessingSecurityScopedResource", source)
        self.assertIn("supportedExtensions", source)
        self.assertNotIn("Process()", source)

    def test_browser_capture_is_explicit_and_per_tab(self):
        manifest = json.loads((EXTENSION / "manifest.json").read_text())
        self.assertEqual(set(manifest["permissions"]), {"nativeMessaging", "offscreen", "tabCapture"})
        self.assertEqual(manifest["action"]["default_popup"], "popup.html")
        popup = (EXTENSION / "popup.js").read_text()
        background = (EXTENSION / "background.js").read_text()
        offscreen = (EXTENSION / "offscreen.js").read_text()
        self.assertIn('"nodebay-enable-eq"', popup)
        self.assertIn("chrome.tabCapture.getMediaStreamId", background)
        self.assertIn("const equalizedTabs = new Set()", background)
        self.assertIn("stopAllEqualizers", background)
        self.assertIn("createBiquadFilter", offscreen)
        self.assertIn("headroom.connect(context.destination)", offscreen)
        self.assertIn("track.stop()", offscreen)
        self.assertNotIn("fetch(", offscreen)

    def test_process_equalizer_is_fail_safe_and_handles_browser_helpers(self):
        self.assertIn("disableEqualizer(sessionID", BRIDGE.read_text())
        self.assertIn("stopBrowserEqualizerIfNeeded", MUSIC.read_text())
        source = MANAGER.read_text()
        self.assertIn("CATapDescription(", source)
        self.assertIn("deviceUID: outputDeviceUID", source)
        self.assertIn("stream: 0", source)
        self.assertNotIn("stereoMixdownOfProcesses", source)
        self.assertIn("tapDescription.muteBehavior = .mutedWhenTapped", source)
        self.assertIn("AudioDeviceCreateIOProcIDWithBlock", source)
        self.assertIn("processor.process(input: inputData, output: outputData)", source)
        self.assertIn("AudioDeviceStart(aggregateDeviceID", source)
        self.assertIn("processBundleID.hasPrefix(requested + \".\")", source)
        self.assertIn('bundleIdentifiers: ["com.google.Chrome"]', source)
        self.assertIn("bundleIdentifiers: [QuickTimeController.bundleIdentifier]", source)
        self.assertIn('identifier.hasPrefix("com.google.Chrome.")', source)
        self.assertIn("type == .nowPlaying, isChromeNowPlaying", source)
        self.assertIn("isChromeNowPlaying || isQuickTimeNowPlaying", source)
        self.assertIn("type == .nowPlaying, isQuickTimeNowPlaying", source)
        self.assertIn("guard !bypassed", source)
        self.assertIn("self.stopOnQueue()", source)
        self.assertIn("BrowserMediaBridge.shared.disableEqualizer", source)

    def test_late_now_playing_bundle_resolution_reapplies_equalizer(self):
        source = MUSIC.read_text()
        self.assertIn("let activeBundleChanged = state.bundleIdentifier != self.bundleIdentifier", source)
        self.assertIn("let activePlaybackChanged = state.isPlaying != self.isPlaying", source)
        self.assertIn("activeBundleChanged || activePlaybackChanged", source)
        self.assertIn("activeSourceID == .controller(.nowPlaying)", source)
        self.assertIn("NodebayEqualizerManager.shared.apply(to: activeSourceID)", source)

    def test_process_equalizer_routes_through_current_output_and_recovers(self):
        source = MANAGER.read_text()
        self.assertIn("kAudioHardwarePropertyDefaultOutputDevice", source)
        self.assertIn("kAudioAggregateDeviceSubDeviceListKey", source)
        self.assertIn("deviceUID: outputDeviceUID", source)
        self.assertIn("AudioDeviceCreateIOProcIDWithBlock", source)
        self.assertIn("AudioDeviceDestroyIOProcID", source)
        self.assertIn("AudioObjectAddPropertyListenerBlock", source)
        self.assertIn("kAudioHardwarePropertyDefaultOutputDevice", source)
        self.assertIn("currentOutput != self.activeOutputDeviceID", source)
        self.assertNotIn("AVAudioEngineConfigurationChange", source)
        self.assertIn("AudioHardwareDestroyAggregateDevice", source)
        self.assertIn("AudioHardwareDestroyProcessTap", source)

    def test_equalizer_defaults_to_active_not_bypassed(self):
        source = MANAGER.read_text()
        self.assertIn('nodebay.equalizer.bypassed") as? Bool ?? false', source)

    def test_homebrew_install_is_fixed_and_shell_free(self):
        helper = HELPER.read_text()
        registry = REGISTRY.read_text()
        settings = SETTINGS.read_text()
        for exact in (
            '["install", "yt-dlp"]',
            '["install", "ffmpeg"]',
            '["install", "--cask", "imageoptim"]',
            '["install", "--cask", "blender"]',
        ):
            self.assertIn(exact, helper)
        self.assertNotIn("brew.sh/install", helper + registry + settings)
        self.assertNotIn("/bin/sh", helper)
        self.assertIn("Homebrew is not installed", registry)
        self.assertIn("Install missing companion apps?", settings)
        self.assertIn("Nodebay never asks for or captures an administrator password", settings)

    def test_extension_scripts_parse(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js unavailable")
        for filename in ("background.js", "media.js", "offscreen.js", "popup.js"):
            subprocess.run([node, "--check", str(EXTENSION / filename)], check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
