//
//  boringNotchApp.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import Darwin
import KeyboardShortcuts
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    private let sparkleUpdaterDelegate: BoringSparkleUpdaterDelegate
    let updaterController: SPUStandardUpdaterController

    init() {
        let sparkleUpdaterDelegate = BoringSparkleUpdaterDelegate()
        self.sparkleUpdaterDelegate = sparkleUpdaterDelegate
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: sparkleUpdaterDelegate, userDriverDelegate: nil)
        SoftwareUpdateStore.shared.configure(updaterController.updater)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra(NodebayBrand.name, systemImage: "shippingbox.fill", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            CheckForUpdatesView(updater: updaterController.updater)
            Button("Restart Nodebay") {
                SoftwareUpdateStore.shared.restartIfIdle()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }
                .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLockFD: Int32 = -1
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: BoringViewModel] = [:] // UUID -> BoringViewModel
    var window: NSWindow?
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var screenConfigurationTask: DispatchWorkItem?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private let dragRouter = NotchDragRoutingCoordinator()
    private var observers: [Any] = []
    private var workspaceObservers: [Any] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Sparkle can skip its postpone callback when resuming an interrupted
        // installation. Recheck current work at the actual termination boundary.
        guard SoftwareUpdateStore.shared.canTerminate() else {
            SoftwareUpdateStore.shared.showBusyNotice()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush debounced shelf persistence to avoid losing recent changes
        ShelfStateViewModel.shared.flushSync()

        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        NotchPasteShortcutMonitor.shared.stop()
        cleanupWindows()
        BetterDisplayManager.shared.stopObserving()
        LunarManager.shared.stopListening()
        LunarManager.shared.configureLunarOSD(hide: false)
        MediaKeyInterceptor.shared.stopMonitoringAccessibilityAuthorization()
        
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        timer?.invalidate()
        screenConfigurationTask?.cancel()
        if instanceLockFD >= 0 {
            flock(instanceLockFD, LOCK_UN)
            close(instanceLockFD)
            instanceLockFD = -1
        }
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? BoringNotchSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? BoringNotchSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? BoringNotchSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? BoringNotchSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.forEach { uuid, window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                QuickChatCoordinator.shared.screen(uuid, open: false)
            }
            windows.removeAll()
            viewModels.values.forEach { $0.destroy() }
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            self.window = nil
            QuickChatCoordinator.shared.screen(vm.screenUUID ?? "default", open: false)
        }

        // ensure OSD integration reflects the current window state
        coordinator.applyOSDSources()
    }

    private func cleanupDragDetectors() {
        dragRouter.stop()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        let targets: [NotchDragRoutingCoordinator.Target]
        if Defaults[.showOnAllDisplays] {
            targets = windows.compactMap { uuid, targetWindow in
                guard let viewModel = viewModels[uuid] else { return nil }
                return dragTarget(uuid: uuid, window: targetWindow, viewModel: viewModel)
            }
        } else if let targetWindow = window, let uuid = vm.screenUUID ?? targetWindow.screen?.displayUUID {
            targets = [dragTarget(uuid: uuid, window: targetWindow, viewModel: vm)]
        } else {
            targets = []
        }
        dragRouter.configure(targets)
    }

    private func dragTarget(
        uuid: String,
        window: NSWindow,
        viewModel: BoringViewModel
    ) -> NotchDragRoutingCoordinator.Target {
        NotchDragRoutingCoordinator.Target(
            displayUUID: uuid,
            region: { [weak window, weak viewModel] in
                guard let frame = window?.frame, let viewModel else { return .null }
                if viewModel.notchState == .open {
                    return CGRect(
                        x: frame.midX - openNotchSize.width / 2,
                        y: frame.maxY - openNotchSize.height,
                        width: openNotchSize.width,
                        height: openNotchSize.height
                    )
                }
                return NotchDragRegion.closed(
                    windowFrame: frame,
                    notchSize: CGSize(
                        width: viewModel.closedNotchSize.width,
                        height: viewModel.effectiveClosedNotchHeight
                    )
                )
            },
            entered: { [weak self] in
                Task { @MainActor in self?.handleDragEntersNotchRegion(displayUUID: uuid) }
            },
            exited: { [weak self] in
                Task { @MainActor in self?.setDragTargeting(false, displayUUID: uuid) }
            }
        )
    }

    private func handleDragEntersNotchRegion(displayUUID uuid: String) {
        guard Defaults[.boringShelf] else { return }
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.dragDetectorTargeting = true
            _ = viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], vm.screenUUID == uuid {
            vm.dragDetectorTargeting = true
            _ = vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func setDragTargeting(_ targeted: Bool, displayUUID uuid: String) {
        if Defaults[.showOnAllDisplays] { viewModels[uuid]?.dragDetectorTargeting = targeted }
        else if vm.screenUUID == uuid { vm.dragDetectorTargeting = targeted }
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrame(
            NSRect(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.maxY - windowSize.height,
                width: windowSize.width,
                height: windowSize.height
            ), display: true)
        window.alphaValue = 1
    }

    private func acquireInstanceLock() -> Bool {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return false
        }
        let directory = caches.appendingPathComponent("Nodebay", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let path = directory.appendingPathComponent("instance.lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            return false
        }
        instanceLockFD = fd
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launching a copied build directly bypasses Launch Services' normal
        // activation of the running app. Only one process may own notch windows.
        guard acquireInstanceLock() else {
            NSApplication.shared.terminate(nil)
            return
        }
        migrateDisplayPlacementPreferenceIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.screenConfigurationDidChange()
            })
        }

        // One owned observer covers every notch window without accumulating
        // orphaned observer tokens as external displays reconnect.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let changedWindow = notification.object as? BoringNotchSkyLightWindow else { return }
            Task { @MainActor in
                guard let self,
                      self.window === changedWindow || self.windows.values.contains(where: { $0 === changedWindow }) else { return }
                self.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .displayPlacementModeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        })

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
                KeyboardShortcuts.onKeyUp(for: .toggleSneakPeek) {
                    self.coordinator.toggleSneakPeek(
                        status: !self.coordinator.isAnySneakPeekShowing,
                        type: .music
                    )
                }
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.isAnySneakPeekShowing,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    var didOpen = false
                    await MainActor.run {
                        didOpen = viewModel.open()
                    }
                    guard didOpen else { return }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        // Sync notch height with real value on app launch if mode is matchRealNotchSize
        syncNotchHeightIfNeeded()
        
        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createBoringNotchWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()
        setupPasteShortcutMonitor()
        installActiveDisplayTracking()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        if !coordinator.firstLaunch {
            DispatchQueue.main.async { SoftwareUpdateStore.shared.presentMigrationChoiceIfNeeded() }
        }
        // make sure OSD subsystems are in the right state now that initial
        // notch windows have been created/cleaned up
        coordinator.applyOSDSources()
    }

    private func setupPasteShortcutMonitor() {
        NotchPasteShortcutMonitor.shared.start(
            shouldHandle: { [weak self] in self?.canPasteIntoHoveredNotch() == true },
            handler: { [weak self] in
                guard let self, QuickNotesCoordinator.shared.pasteIfSupported() else { return false }
                self.coordinator.currentView = .shelf
                return true
            }
        )
    }

    private func canPasteIntoHoveredNotch() -> Bool {
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        let pointer = NSEvent.mouseLocation
        if Defaults[.showOnAllDisplays] {
            return windows.contains { uuid, window in
                guard viewModels[uuid]?.notchState == .open else { return false }
                return openNotchRegion(for: window).contains(pointer)
            }
        }
        guard vm.notchState == .open, let window else { return false }
        return openNotchRegion(for: window).contains(pointer)
    }

    private func openNotchRegion(for window: NSWindow) -> CGRect {
        CGRect(
            x: window.frame.midX - openNotchSize.width / 2,
            y: window.frame.maxY - openNotchSize.height,
            width: openNotchSize.width,
            height: openNotchSize.height
        )
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        // Display notifications also cover scale, safe area and arrangement
        // changes with unchanged display IDs. Read fresh geometry after the
        // notification batch, and retain unaffected hosting views and drafts.
        screenConfigurationTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenConfigurationTask = nil
            NSScreenUUIDCache.shared.refresh()
            syncNotchHeightIfNeeded()
            self.adjustWindowPosition()
            self.setupDragDetectors()
        }
        screenConfigurationTask = task
        DispatchQueue.main.async(execute: task)
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        guard !isScreenLocked || Defaults[.showOnLockScreen] else { return }
        // A reconfiguration can briefly report no screens. Hide the existing
        // surfaces until the next update instead of destroying their state.
        guard !NSScreen.screens.isEmpty else {
            window?.alphaValue = 0
            windows.values.forEach { $0.alphaValue = 0 }
            return
        }
        // Display-mode notifications may be coalesced or arrive after a new
        // window is created. Retire the other mode's windows before positioning.
        if (Defaults[.showOnAllDisplays] && window != nil)
            || (!Defaults[.showOnAllDisplays] && !windows.isEmpty) {
            cleanupWindows(shouldInvert: true)
        }
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    QuickChatCoordinator.shared.screen(uuid, open: false)
                    windows.removeValue(forKey: uuid)
                    viewModels[uuid]?.destroy()
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = BoringViewModel(screenUUID: uuid)
                    let window = createBoringNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    viewModel.refreshDisplayGeometry(screenUUID: uuid)
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let resolvedScreen = resolvedSingleDisplay() {
                selectedScreen = resolvedScreen
                coordinator.selectedScreenUUID = resolvedScreen.displayUUID ?? ""
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.refreshDisplayGeometry(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createBoringNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)
            }
        }

        // AppKit retains ordered windows even if our bookkeeping loses one.
        // A stale notch window still receives hover/scroll events and makes one
        // gesture appear to open or close twice on the same display.
        let ownedWindows: [NSWindow] = Defaults[.showOnAllDisplays]
            ? Array(windows.values) : window.map { [$0] } ?? []
        for staleWindow in NSApp.windows where staleWindow is BoringNotchSkyLightWindow
            && !ownedWindows.contains(where: { $0 === staleWindow }) {
            staleWindow.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(staleWindow)
        }

        // windows might have been added/removed during the earlier logic –
        // update the OSD subsystems accordingly.
        coordinator.applyOSDSources()
    }

    @MainActor
    private func resolvedSingleDisplay() -> NSScreen? {
        let fallback = NSScreen.main ?? NSScreen.screens.first
        switch Defaults[.displayPlacementMode] {
        case .all:
            return fallback
        case .builtIn:
            return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? fallback
        case .specific:
            return NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") ?? fallback
        case .main:
            return fallback
        case .followActive:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? fallback
        }
    }

    private func installActiveDisplayTracking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard Defaults[.displayPlacementMode] == .followActive else { return }
            Task { @MainActor in
                guard let self,
                      let target = self.resolvedSingleDisplay(),
                      target.displayUUID != self.coordinator.selectedScreenUUID else { return }
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }
    }

    private func migrateDisplayPlacementPreferenceIfNeeded() {
        let key = "nodebayDisplayPlacementMode"
        guard UserDefaults.standard.object(forKey: key) == nil else {
            Defaults[.showOnAllDisplays] = Defaults[.displayPlacementMode] == .all
            return
        }
        if Defaults[.showOnAllDisplays] {
            Defaults[.displayPlacementMode] = .all
        } else if Defaults[.automaticallySwitchDisplay] {
            Defaults[.displayPlacementMode] = .followActive
        } else {
            Defaults[.displayPlacementMode] = .specific
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.level = .floating
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    updater: SoftwareUpdateStore.updater,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.level = .floating
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}
