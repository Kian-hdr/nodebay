//
//  BoringViewCoordinator.swift
//  boringNotch
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import SwiftUI

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var accent: Color? = nil
    var targetScreenUUID: String? = nil
}

struct SharedSneakPeek: Codable {
    var show: Bool
    var type: String
    var value: String
    var icon: String
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()

    @Published var currentView: NotchViews = .home
    @Published var helloAnimationRunning: Bool = false
    private var sneakPeekDispatch: DispatchWorkItem?
    private var expandingViewDispatch: DispatchWorkItem?
    private var osdEnableTask: Task<Void, Never>?

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var osdReplacementCancellable: AnyCancellable?
    private var boringShelfCancellable: AnyCancellable?
    private var osdSourceCancellables: [AnyCancellable] = []
    private var hudLifecycleObservers: [NSObjectProtocol] = []

    private init() {
        Self.migrateLegacyOSDPreferencesIfNeeded()

        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.osdReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // The media-key event tap lives in the main Nodebay process, so its
        // Accessibility grant must be checked here rather than in the XPC
        // processing helper. Checking the helper made an already-authorized
        // Nodebay installation appear unauthorized and prevented HUD startup.
        MediaKeyInterceptor.shared.startMonitoringAccessibilityAuthorization()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        hudLifecycleObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverHUD() }
        })
        hudLifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverHUD() }
        })
        hudLifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverHUD() }
        })

        // Observe changes to osdReplacement
        osdReplacementCancellable = Defaults.publisher(.osdReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.osdEnableTask?.cancel()
                    self.osdEnableTask = nil

                    if change.newValue {
                        self.osdEnableTask = Task { @MainActor in
                            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                    
                    self.applyOSDSources()
                }
            }
        // Observe changes to any of the OSD source selections
        osdSourceCancellables = [
            Defaults.publisher(.osdBrightnessSource).sink { [weak self] _ in Task { @MainActor in self?.applyOSDSources() } },
            Defaults.publisher(.osdVolumeSource).sink { [weak self] _ in Task { @MainActor in self?.applyOSDSources() } }
        ]
        boringShelfCancellable = Defaults.publisher(.boringShelf)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }
                    if !change.newValue && self.currentView == .shelf {
                        self.currentView = .home
                    }
                }
            }

        Task { @MainActor in
            helloAnimationRunning = firstLaunch

            if Defaults[.osdReplacement] {
                await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            }
            self.applyOSDSources()
        }
    }

    private func recoverHUD() {
        guard Defaults[.osdReplacement] else { return }
        Task { @MainActor in
            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
            self.applyOSDSources()
        }
    }

    /// The upstream HUD-to-OSD rename changed persisted key names without
    /// migrating existing installations. Preserve the user's previous HUD
    /// choices once, before the OSD controller reads them.
    private static func migrateLegacyOSDPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "nodebayDidMigrateLegacyOSDPreferences"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let mappings = [
            (legacy: "hudReplacement", current: "osdReplacement"),
            (legacy: "inlineHUD", current: "inlineOSD"),
            (legacy: "showOpenNotchHUD", current: "showOpenNotchOSD"),
            (legacy: "showOpenNotchHUDPercentage", current: "showOpenNotchOSDPercentage"),
            (legacy: "showClosedNotchHUDPercentage", current: "showClosedNotchOSDPercentage"),
        ]

        for mapping in mappings where defaults.object(forKey: mapping.current) == nil {
            if let legacyValue = defaults.object(forKey: mapping.legacy) {
                defaults.set(legacyValue, forKey: mapping.current)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        let decoder = JSONDecoder()
        if let decodedData = try? decoder.decode(
            SharedSneakPeek.self, from: notification.userInfo?.first?.value as! Data)
        {
            let contentType =
                decodedData.type == "brightness"
                ? SneakContentType.brightness
                : decodedData.type == "volume"
                    ? SneakContentType.volume
                    : decodedData.type == "backlight"
                        ? SneakContentType.backlight
                        : decodedData.type == "mic"
                            ? SneakContentType.mic : SneakContentType.brightness

            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .decimal
            let value = CGFloat((formatter.number(from: decodedData.value) ?? 0.0).floatValue)
            let icon = decodedData.icon

            print("Decoded: \(decodedData), Parsed value: \(value)")

            toggleSneakPeek(status: decodedData.show, type: contentType, value: value, icon: icon)

        } else {
            print("Failed to decode JSON data")
        }
    }

    // MARK: - Per-Screen Sneak Peek Management

    // Dictionary to hold sneak peek state for each screen UUID
    @Published var sneakPeekStates: [String: sneakPeek] = [:]
    
    // Dictionary to hold hide tasks for each screen UUID
    private var sneakPeekTasks: [String: Task<Void, Never>] = [:]
    
    // Default duration
    private var defaultSneakPeekDuration: TimeInterval = 1.5

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0,
        icon: String = "", accent: Color? = nil, targetScreenUUID: String? = nil
    ) {
        if type != .music {
            // close()
            if !Defaults[.osdReplacement] {
                return
            }
        }
        
        Task { @MainActor in
            // Helper to update state for a specific UUID
            @MainActor
            func updateState(for uuid: String) {
                // If we don't have a state for this screen yet, initialize it
                var state = self.sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
                
                withAnimation(.smooth) {
                    state.show = status
                    state.type = type
                    state.value = value
                    state.icon = icon
                    state.accent = accent
                    state.targetScreenUUID = uuid // Ensure UUID is set
                    self.sneakPeekStates[uuid] = state
                }
                
                if status {
                    self.scheduleSneakPeekHide(for: uuid, duration: duration)
                } else {
                    self.sneakPeekTasks[uuid]?.cancel()
                    self.sneakPeekTasks[uuid] = nil
                }
            }
            
            let isHUD = type == .brightness || type == .volume || type == .backlight
            if isHUD {
                let targets = self.hudTargetScreenUUIDs(explicitTarget: targetScreenUUID)
                for uuid in targets {
                    updateState(for: uuid)
                }
                HUDDiagnostics.shared.updateActiveDisplay(self.hudDisplayDescription(for: targets))
            } else if let targetUUID = targetScreenUUID {
                updateState(for: targetUUID)
            } else {
                // Update ALL connected screens + the main screen as fallback
                // We use known screen UUIDs from NSScreen
                let screens = NSScreen.screens.compactMap { $0.displayUUID }
                if screens.isEmpty {
                    // Fallback if no screens detected (unlikely in UI app but safe)
                     if let mainUUID = NSScreen.main?.displayUUID {
                         updateState(for: mainUUID)
                     }
                } else {
                    for uuid in screens {
                        updateState(for: uuid)
                    }
                }
            }
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    /// Resolve HUD presentation using the same persistent display policy as
    /// the Nodebay window. The affected hardware display is used only in
    /// follow-active mode; explicit user placement remains authoritative.
    func hudTargetScreenUUIDs(explicitTarget: String? = nil) -> [String] {
        let screens = NSScreen.screens
        let fallback = (NSScreen.main ?? screens.first)?.displayUUID

        switch Defaults[.displayPlacementMode] {
        case .all:
            return screens.compactMap(\.displayUUID)
        case .builtIn:
            return [screens.first(where: { $0.safeAreaInsets.top > 0 })?.displayUUID ?? fallback].compactMap { $0 }
        case .specific:
            let selected = preferredScreenUUID.flatMap { NSScreen.screen(withUUID: $0)?.displayUUID }
            return [selected ?? fallback].compactMap { $0 }
        case .main:
            return [fallback].compactMap { $0 }
        case .followActive:
            if let explicitTarget, NSScreen.screen(withUUID: explicitTarget) != nil {
                return [explicitTarget]
            }
            if NSScreen.screen(withUUID: selectedScreenUUID) != nil {
                return [selectedScreenUUID]
            }
            let pointer = NSEvent.mouseLocation
            let pointerTarget = screens.first(where: { $0.frame.contains(pointer) })?.displayUUID
            return [pointerTarget ?? fallback].compactMap { $0 }
        }
    }

    private func hudDisplayDescription(for targets: [String]) -> String {
        guard !targets.isEmpty else { return "Unavailable" }
        if targets.count > 1 { return "All displays (\(targets.count))" }
        guard let screen = NSScreen.screen(withUUID: targets[0]) else { return "Unavailable" }
        return "\(screen.localizedName) (\(targets[0].prefix(8)))"
    }

     func applyOSDSources() {
        guard Defaults[.osdReplacement] else {
            BetterDisplayManager.shared.stopObserving()
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
            MediaKeyInterceptor.shared.stop()
            return
        }

        let brightness = Defaults[.osdBrightnessSource]
        let volume = Defaults[.osdVolumeSource]

        Task { @MainActor in
            await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
        }

        // Keep built-in media-key interception alive while notch windows are
        // being recreated. Stopping it during the short window-less interval
        // made the HUD remain disabled after launch, wake, or display changes.
        // External OSD providers still wait until a visible notch exists.
        if NotchSpaceManager.shared.notchSpace.windows.isEmpty {
            BetterDisplayManager.shared.stopObserving()
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
            return
        }

        // BetterDisplay is used when either brightness or volume is set to it
        if brightness == .betterDisplay || volume == .betterDisplay {
            BetterDisplayManager.shared.startObserving()
        } else {
            BetterDisplayManager.shared.stopObserving()
        }

        // Lunar only supports brightness; disable Lunar's OSD when we replace it, restore when we don't
        if brightness == .lunar {
            LunarManager.shared.configureLunarOSD(hide: true)
            LunarManager.shared.startListening()
        } else {
            LunarManager.shared.stopListening()
            LunarManager.shared.configureLunarOSD(hide: false)
        }
    }

    func shouldShowSneakPeek(on screenUUID: String?) -> Bool {
        guard let uuid = screenUUID else { return false }
        return sneakPeekStates[uuid]?.show == true
    }
    
    var isAnySneakPeekShowing: Bool {
        return sneakPeekStates.values.contains { $0.show }
    }
    
    // Helper to get state safely for binding/reading
    func sneakPeekState(for screenUUID: String?) -> sneakPeek {
        guard let uuid = screenUUID else { return sneakPeek() }
        return sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
    }
    
    // Helper to get binding for SwiftUI views
    func binding(for screenUUID: String?) -> Binding<sneakPeek> {
        Binding(
            get: { [weak self] in
                guard let self = self, let uuid = screenUUID else { return sneakPeek() }
                return self.sneakPeekStates[uuid] ?? sneakPeek(targetScreenUUID: uuid)
            },
            set: { [weak self] newValue in
                guard let self = self, let uuid = screenUUID else { return }
                self.sneakPeekStates[uuid] = newValue
            }
        )
    }

    private func scheduleSneakPeekHide(for screenUUID: String, duration: TimeInterval) {
        sneakPeekTasks[screenUUID]?.cancel()

        sneakPeekTasks[screenUUID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            
            await MainActor.run {
                withAnimation {
                    // We only want to hide it, not reset everything instantly which might cause glitches
                    if var state = self.sneakPeekStates[screenUUID] {
                         state.show = false
                         // Optional: reset type to something default if needed, but keeping last state is often fine until next show
                         // keeping original logic:
                         state.type = .music 
                         self.sneakPeekStates[screenUUID] = state
                    }
                }
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }
    
    func showEmpty() {
        currentView = .home
    }
}
