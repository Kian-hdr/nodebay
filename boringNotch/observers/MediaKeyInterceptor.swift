//
//  MediaKeyInterceptor.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-23.

import Foundation
import AppKit
import ApplicationServices
import Combine
import Defaults
import AVFoundation

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

@MainActor
final class HUDDiagnostics: ObservableObject {
    static let shared = HUDDiagnostics()

    @Published private(set) var hudEnabled = false
    @Published private(set) var accessibilityStatus = "Unauthorized"
    @Published private(set) var eventTapStatus = "Inactive"
    @Published private(set) var volumeProvider = "Built-in"
    @Published private(set) var brightnessProvider = "Built-in"
    @Published private(set) var activeDisplay = "Unavailable"
    @Published private(set) var lastRecoverableError: String?

    private init() {}

    func updateConfiguration() {
        hudEnabled = Defaults[.osdReplacement]
        volumeProvider = Defaults[.osdVolumeSource].localizedString
        brightnessProvider = Defaults[.osdBrightnessSource].localizedString
    }

    func updateAuthorization(_ authorized: Bool, previouslyAuthorized: Bool) {
        accessibilityStatus = authorized
            ? "Authorized for this signed app"
            : previouslyAuthorized
                ? "Authorization changed; reauthorization required"
                : "Unauthorized"
    }

    func updateEventTap(_ status: String, error: String? = nil) {
        eventTapStatus = status
        if let error {
            lastRecoverableError = error
        }
    }

    func updateActiveDisplay(_ display: String) {
        activeDisplay = display
    }

    func clearError() {
        lastRecoverableError = nil
    }
}

final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private enum NXKeyType: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityMonitorTask: Task<Void, Never>?
    private var lastKnownAccessibilityAuthorization: Bool?
    private var brightnessSupported = false
    private var keyboardBacklightSupported = false
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}

    private var isTapActive: Bool {
        guard let eventTap, runLoopSource != nil else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    // MARK: - Accessibility

    @MainActor
    func requestAccessibilityAuthorization() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    @MainActor
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        var authorized = AXIsProcessTrusted()
        publishAccessibilityAuthorization(authorized)

        guard !authorized, promptIfNeeded else { return authorized }
        requestAccessibilityAuthorization()
        try? await Task.sleep(for: .milliseconds(500))
        authorized = AXIsProcessTrusted()
        publishAccessibilityAuthorization(authorized)
        return authorized
    }

    @MainActor
    func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        stopMonitoringAccessibilityAuthorization()
        accessibilityMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let authorized = AXIsProcessTrusted()
                publishAccessibilityAuthorization(authorized)

                // Accessibility can already be granted when Nodebay launches,
                // and the notch window can be recreated after display, Space,
                // lock-screen, or wake changes. Recover the media-key tap here
                // instead of relying on a one-time startup callback.
                if authorized && Defaults[.osdReplacement] && !isTapActive {
                    await start(promptIfNeeded: false)
                }
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    break
                }
            }
        }
    }

    @MainActor
    func stopMonitoringAccessibilityAuthorization() {
        accessibilityMonitorTask?.cancel()
        accessibilityMonitorTask = nil
    }

    @MainActor
    private func publishAccessibilityAuthorization(_ authorized: Bool) {
        let marker = "nodebayAccessibilityWasAuthorized"
        if authorized {
            UserDefaults.standard.set(true, forKey: marker)
        }
        HUDDiagnostics.shared.updateAuthorization(
            authorized,
            previouslyAuthorized: UserDefaults.standard.bool(forKey: marker)
        )
        guard lastKnownAccessibilityAuthorization != authorized else { return }
        lastKnownAccessibilityAuthorization = authorized
        NSLog("Nodebay HUD Accessibility authorization: %@", authorized ? "granted" : "denied")
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": authorized]
        )
    }

    // MARK: - Event Tap
    
    @MainActor
    func start(promptIfNeeded: Bool = false) async {
        HUDDiagnostics.shared.updateConfiguration()
        // Ensure OSD replacement is enabled
        guard Defaults[.osdReplacement] else {
            stop()
            return
        }

        // A modifying event tap can suppress the native OSD only when the
        // currently running, signed Nodebay executable is trusted. External
        // providers can still publish their own notifications without this tap.
        let authorized = AXIsProcessTrusted()
        publishAccessibilityAuthorization(authorized)
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else { return }
            } else {
                HUDDiagnostics.shared.updateEventTap(
                    "Inactive",
                    error: "Accessibility is not authorized for the running Nodebay executable."
                )
                return
            }
        }

        if Defaults[.osdBrightnessSource] == .builtin {
            brightnessSupported = await BrightnessManager.shared.refreshSupport()
        } else {
            brightnessSupported = false
        }
        keyboardBacklightSupported = await KeyboardBacklightManager.shared.refreshSupport()

        if let eventTap, isTapActive {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            HUDDiagnostics.shared.updateEventTap("Active")
            return
        }

        if eventTap != nil || runLoopSource != nil {
            stop()
        }

        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    interceptor.reenableEventTap(after: type)
                    return nil
                }

                return interceptor.handleEvent(cgEvent)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            NSLog("Nodebay HUD media-key event tap started")
            HUDDiagnostics.shared.updateEventTap("Active")
            HUDDiagnostics.shared.clearError()
        } else {
            NSLog("Nodebay HUD media-key event tap failed to start")
            HUDDiagnostics.shared.updateEventTap(
                "Failed",
                error: "The media-key event tap could not be created. Check Accessibility access, then retry."
            )
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        Task { @MainActor in
            HUDDiagnostics.shared.updateEventTap("Inactive")
        }
    }

    private func reenableEventTap(after type: CGEventType) {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)

        let reason: String
        switch type {
        case .tapDisabledByTimeout:
            reason = "timeout"
        case .tapDisabledByUserInput:
            reason = "user input"
        default:
            reason = "unknown reason"
        }

        let enabled = CGEvent.tapIsEnabled(tap: eventTap)
        Task { @MainActor in
            HUDDiagnostics.shared.updateEventTap(
                enabled ? "Active" : "Recovering",
                error: enabled ? nil : "The event tap was disabled after \(reason) and is being recovered."
            )
        }
        NSLog("Nodebay HUD event tap %@ after %@", enabled ? "re-enabled" : "failed to re-enable", reason)
    }

    // MARK: - Event Handling

    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // Ensure the CGEvent has a valid type before converting to NSEvent
        guard cgEvent.type != .null else {
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)

        // 0xA = key down, 0xB = key up. Preserve unrelated system events.
        guard (stateByte == 0xA || stateByte == 0xB),
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passUnretained(cgEvent)
        }

        // Determine which source is selected for this control (brightness/volume/keyboard)
        let selectedSource: OSDControlSource = {
            switch keyType {
            case .soundUp, .soundDown, .mute:
                return Defaults[.osdVolumeSource]
            case .brightnessUp, .brightnessDown:
                return Defaults[.osdBrightnessSource]
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                return .builtin
            }
        }()

        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)

        // If an external source is selected and available, allow the event to pass through (external app will emit OSD notifications)
        switch selectedSource {
        case .betterDisplay:
            if BetterDisplayManager.shared.isBetterDisplayAvailable {
                if (keyType == .brightnessUp || keyType == .brightnessDown) && command {
                    break
                }
                return Unmanaged.passUnretained(cgEvent)
            }
            return Unmanaged.passUnretained(cgEvent)
        case .lunar:
            if LunarManager.shared.isLunarAvailable {
                if (keyType == .brightnessUp || keyType == .brightnessDown) && command {
                    break
                }
                return Unmanaged.passUnretained(cgEvent)
            }
            return Unmanaged.passUnretained(cgEvent)
        case .builtin:
            break
        }

        guard canHandle(keyType, command: command) else {
            Task { @MainActor in
                HUDDiagnostics.shared.updateEventTap(
                    "Active",
                    error: "The selected built-in provider cannot control this device; the key was passed to macOS."
                )
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // Consume the matching key-up only when Nodebay owns the key-down.
        guard stateByte == 0xA else { return nil }

        // Handle option key action (without shift)
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }

        // Handle normal key press
        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        return nil
    }

    private func canHandle(_ keyType: NXKeyType, command: Bool) -> Bool {
        switch keyType {
        case .soundUp, .soundDown:
            return VolumeManager.shared.canControlVolume
        case .mute:
            return VolumeManager.shared.canControlMute
        case .brightnessUp, .brightnessDown:
            return command ? keyboardBacklightSupported : brightnessSupported
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            return keyboardBacklightSupported
        }
    }

    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]

        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showOSD:
            showOSD(for: keyType, command: command)
            return true
        case .none:
            return true
        }
    }

    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
                print("🔊 [MediaKeyInterceptor] Loaded default Bezel audio from: \(defaultPath)")
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer with default path \(defaultPath): \(error.localizedDescription)")
            }
        } else {
            print("⚠️ [MediaKeyInterceptor] Default bezel audio not found at: \(defaultPath)")
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else {
            print("⚠️ [MediaKeyInterceptor] No audio player available to play feedback sound")
            return
        }
        if let url = player.url {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound from: \(url.path)")
        } else {
            print("🔊 [MediaKeyInterceptor] Playing feedback sound (no url available for AVAudioPlayer)")
        }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0

        switch keyType {
        case .soundUp:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }

    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }

    private func showOSD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
            switch keyType {
            case .soundUp, .soundDown, .mute:
                let v = VolumeManager.shared.rawVolume
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
            case .brightnessUp, .brightnessDown:
                if command {
                    let v = KeyboardBacklightManager.shared.rawBrightness
                    BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
                } else {
                    let v = BrightnessManager.shared.rawBrightness
                    Task { @MainActor in
                        let target = await BrightnessManager.shared.brightnessTargetUUID()
                        BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v), targetScreenUUID: target)
                    }
                }
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                let v = KeyboardBacklightManager.shared.rawBrightness
                BoringViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
            }
        }
    }

    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String

        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            if command {
                urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.displays"
            }
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
