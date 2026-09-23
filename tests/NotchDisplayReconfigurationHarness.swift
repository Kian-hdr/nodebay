// Window/server and application-service doubles only. The Python test compiles
// these with production view-model properties and display-routing method bodies.
// No NSApplication, live displays, preferences, media, or windows are touched.
import Combine
import CoreGraphics
import Foundation

enum NotchState { case open, closed }
enum SelectedTab { case home, shelf, chat }
enum DisplayPlacementMode { case all, builtIn, specific, main, followActive }
struct FixtureKey<Value> { let name: String; let fallback: Value }
extension FixtureKey where Value == Bool {
    static let showOnAllDisplays = Self(name: "all", fallback: false)
    static let showOnLockScreen = Self(name: "lock", fallback: false)
    static let boringShelf = Self(name: "shelf", fallback: true)
    static let openShelfByDefault = Self(name: "defaultShelf", fallback: false)
}
extension FixtureKey where Value == DisplayPlacementMode {
    static let displayPlacementMode = Self(name: "placement", fallback: .specific)
}
@MainActor enum Defaults {
    static var values: [String: Any] = [:]
    static subscript<T>(key: FixtureKey<T>) -> T {
        get { values[key.name] as? T ?? key.fallback }
        set { values[key.name] = newValue }
    }
}
@MainActor final class UserDefaults {
    static let standard = UserDefaults()
    func bool(forKey: String) -> Bool { false }
}
@MainActor final class FixtureCoordinator {
    static let shared = FixtureCoordinator()
    var firstLaunch = false
    var currentView: SelectedTab = .home
    var openLastTabByDefault = true
    var selectedScreenUUID = ""
    var preferredScreenUUID: String? = "A"
    var osdRefreshes = 0
    func shouldShowSneakPeek(on: String?) -> Bool { false }
    enum SneakType { case music }
    func toggleSneakPeek(status: Bool, type: SneakType, targetScreenUUID: String?) {}
    func applyOSDSources() { osdRefreshes += 1 }
}
@MainActor final class QuickChatCoordinator {
    static let shared = QuickChatCoordinator()
    var openScreens = Set<String>()
    var visibilityEvents: [String] = []
    var unfinished = false
    var available = false
    func screen(_ id: String, open: Bool) {
        visibilityEvents.append("\(open ? "open" : "close"):\(id)")
        if open { openScreens.insert(id) } else { openScreens.remove(id) }
    }
}
enum QuickChatPolicy {
    enum Tab { case home, shelf, chat }
    static func openingTab(automatic: Bool, existing: Tab, drag: Bool,
                           unfinished: Bool, media: Bool, shelf: Bool, ready: Bool) -> Tab { existing }
}
@MainActor final class MusicManager {
    static let shared = MusicManager()
    var isPlayerIdle = true
    func forceUpdate() {}
}
@MainActor final class ShelfStateViewModel {
    static let shared = ShelfStateViewModel()
    var isEmpty = true
    func dismissRemovalNotice() {}
}
@MainActor final class SharingStateManager {
    static let shared = SharingStateManager()
    var preventNotchClose = false
}

@MainActor final class NSScreen: NSObject {
    static var screens: [NSScreen] = []
    static var main: NSScreen? { screens.first }
    let displayUUID: String?
    var frame: CGRect
    var visibleFrame: CGRect
    var backingScaleFactor: CGFloat = 2
    struct Insets { var top: CGFloat = 0 }
    var safeAreaInsets = Insets()
    var closedSize: CGSize
    init(_ id: String, x: CGFloat = 0, height: CGFloat = 38) {
        displayUUID = id
        frame = CGRect(x: x, y: 0, width: 1600, height: 1000)
        visibleFrame = CGRect(x: x, y: 0, width: 1600, height: 1000 - height)
        closedSize = CGSize(width: 185, height: height)
    }
    static func screen(withUUID uuid: String) -> NSScreen? { screens.first { $0.displayUUID == uuid } }
}
@MainActor final class NSScreenUUIDCache {
    static let shared = NSScreenUUIDCache()
    var refreshCount = 0
    func refresh() { refreshCount += 1 }
}
@MainActor enum NSEvent { static var mouseLocation = CGPoint(x: 800, y: 990) }
@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    (screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main)?.closedSize
        ?? CGSize(width: 185, height: 29)
}
@MainActor func syncNotchHeightIfNeeded() {}
@MainActor class NSWindow: NSObject {
    var frame = CGRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
    var alphaValue: CGFloat = 1
    var closed = false
    var displayCalls = 0
    func setFrameOrigin(_ origin: CGPoint) { frame.origin = origin }
    func setFrame(_ frame: CGRect, display: Bool) { self.frame = frame; displayCalls += 1 }
    func close() { closed = true }
}
@MainActor final class BoringNotchSkyLightWindow: NSWindow {}
@MainActor final class FixtureApplication {
    static let shared = FixtureApplication()
    var windows: [NSWindow] = []
}
@MainActor var NSApp: FixtureApplication { FixtureApplication.shared }
@MainActor final class NotchSpaceManager {
    static let shared = NotchSpaceManager()
    final class Space { var windows = Set<NSWindow>() }
    let notchSpace = Space()
}

struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FixtureFailure(description: message) }
}

@main struct DisplayReconfigurationHarness {
    @MainActor static func main() async {
        do {
            try await run(CommandLine.arguments[1])
            print("Display reconfiguration checks passed")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor static func drainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor static func run(_ scenario: String) async throws {
        let a = NSScreen("A", height: 38)
        let b = NSScreen("B", x: 1600, height: 29)
        NSScreen.screens = [a]
        let app = AppDelegate()
        app.adjustWindowPosition()
        switch scenario {
        case "open-route":
            _ = app.vm.open()
            let original = app.window
            NSScreen.screens = [a, b]
            app.coordinator.preferredScreenUUID = "B"
            app.adjustWindowPosition(changeAlpha: true)
            try expect(app.vm.notchState == .open, "Open route must preserve state")
            try expect(app.vm.notchSize == openNotchSize, "Open hotplug size must remain 640x190")
            try expect(app.vm.closedNotchSize == b.closedSize, "New display closed geometry must refresh")
            try expect(app.window === original, "Display routing must retain the hosting window")
            try expect(QuickChatCoordinator.shared.openScreens == ["B"], "Chat visibility must migrate to the new display")
            let headerHeight = max(30, app.vm.closedNotchSize.height)
            try expect(max(0, app.vm.notchSize.height - headerHeight - 20) > 0, "Open tab content must remain visible")
            b.closedSize.height = 45
            app.adjustWindowPosition()
            try expect(app.vm.notchSize == openNotchSize && app.vm.closedNotchSize.height == 45,
                       "Height preference refresh must preserve open geometry")
            Defaults[.displayPlacementMode] = .followActive
            NSEvent.mouseLocation = CGPoint(x: a.frame.midX, y: a.frame.maxY - 1)
            app.adjustWindowPosition()
            try expect(app.vm.screenUUID == "A" && app.vm.notchSize == openNotchSize, "Follow-active route must preserve open geometry")
            app.onScreenLocked(Notification(name: .init("fixture.lock")))
            app.onScreenUnlocked(Notification(name: .init("fixture.unlock")))
            try expect(app.vm.notchState == .open && app.vm.notchSize == openNotchSize,
                       "Unlock must not leave an open model at its closed size")
        case "closed-refresh":
            let original = app.window
            SharingStateManager.shared.preventNotchClose = true
            a.closedSize = CGSize(width: 210, height: 44)
            app.adjustWindowPosition()
            try expect(app.vm.notchState == .closed, "Geometry refresh must not open a closed surface")
            try expect(app.vm.notchSize == a.closedSize && app.vm.closedNotchSize == a.closedSize,
                       "Closed geometry refresh must not depend on permission to close")
            try expect(app.window === original, "Height changes must preserve the host")
        case "single-reconciliation":
            _ = app.vm.open()
            let original = app.window
            let model = app.vm
            NSScreen.screens = [a, b]
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(app.window === original && app.vm === model, "Hotplug must retain an unaffected single-display host and model")
            try expect(app.vm.notchState == .open && app.vm.notchSize == openNotchSize, "Hotplug reconciliation must preserve open geometry")
        case "all-reconciliation":
            Defaults[.showOnAllDisplays] = true
            Defaults[.displayPlacementMode] = .all
            NSScreen.screens = [a, b]
            app.adjustWindowPosition()
            let aWindow = app.windows["A"]!
            let bWindow = app.windows["B"]!
            let aModel = app.viewModels["A"]!
            let bModel = app.viewModels["B"]!
            _ = aModel.open(); _ = bModel.open()
            let c = NSScreen("C", x: 3200, height: 31)
            NSScreen.screens = [a, b, c]
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(app.windows["A"] === aWindow && app.windows["B"] === bWindow,
                       "Adding a display must retain existing hosting windows")
            try expect(app.viewModels["A"] === aModel && app.viewModels["B"] === bModel,
                       "Adding a display must retain existing models")
            try expect(aModel.notchState == .open && bModel.notchState == .open, "Adding a display must preserve open state")
            NSScreen.screens = [a, c]
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(bWindow.closed && app.windows["B"] == nil && app.viewModels["B"] == nil,
                       "Only absent displays should be retired")
            try expect(app.windows["A"] === aWindow && !aWindow.closed, "Retiring another display must preserve A")
            try expect(!QuickChatCoordinator.shared.openScreens.contains("B"), "Removed display must relinquish chat visibility")
        case "same-frame-scale":
            app.screenConfigurationDidChange()
            await drainQueue()
            let original = app.window
            let before = app.coordinator.osdRefreshes
            a.backingScaleFactor = 1
            a.closedSize.height = 29
            a.visibleFrame.size.height = 971
            app.screenConfigurationDidChange()
            app.screenConfigurationDidChange()
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(app.vm.closedNotchSize.height == 29, "Unchanged point frames must still refresh scale/safe-area geometry")
            try expect(app.window === original, "Scale refresh must retain its host")
            try expect(app.coordinator.osdRefreshes == before + 1, "A notification burst must reconcile once")
        case "arrangement-swap":
            Defaults[.showOnAllDisplays] = true
            Defaults[.displayPlacementMode] = .all
            NSScreen.screens = [a, b]
            app.adjustWindowPosition()
            app.screenConfigurationDidChange()
            await drainQueue()
            let aWindow = app.windows["A"]!
            let bWindow = app.windows["B"]!
            let previousA = a.frame
            a.frame = b.frame
            b.frame = previousA
            // UUID and frame sets have not changed, only their association.
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(aWindow.frame.midX == a.frame.midX && bWindow.frame.midX == b.frame.midX,
                       "Display geometry must remain associated with its UUID")
            try expect(app.windows["A"] === aWindow && app.windows["B"] === bWindow,
                       "Rearrangement must reposition the same hosting windows")
        case "empty-restoration":
            _ = app.vm.open()
            let original = app.window
            NSScreen.screens = []
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(app.window === original && original?.closed == false, "Transient empty display lists must preserve the host")
            try expect(original?.alphaValue == 0, "Transient empty display lists should hide the host")
            NSScreen.screens = [a]
            app.screenConfigurationDidChange()
            await drainQueue()
            try expect(app.window === original && original?.alphaValue == 1, "Restoration should reuse and reveal the host")
            try expect(app.vm.notchState == .open && app.vm.notchSize == openNotchSize, "Restoration must preserve open geometry")
        case "empty-all-restoration":
            Defaults[.showOnAllDisplays] = true
            NSScreen.screens = [a, b]
            app.adjustWindowPosition()
            let originalWindows = app.windows
            let originalModels = app.viewModels
            for model in originalModels.values { _ = model.open() }
            NSScreen.screens = []
            app.screenConfigurationDidChange()
            await drainQueue()
            for (uuid, window) in originalWindows {
                try expect(app.windows[uuid] === window && !window.closed && window.alphaValue == 0,
                           "Transient empty display lists must hide and retain every host")
            }
            NSScreen.screens = [a, b]
            app.screenConfigurationDidChange()
            await drainQueue()
            for (uuid, window) in originalWindows {
                try expect(app.windows[uuid] === window && window.alphaValue == 1,
                           "Restoration must reveal every original host")
                try expect(app.viewModels[uuid] === originalModels[uuid] && app.viewModels[uuid]?.notchSize == openNotchSize,
                           "Restoration must preserve every open model")
            }
        case "canvas-repair":
            _ = app.vm.open()
            app.window?.frame.size = CGSize(width: 185, height: 38)
            app.adjustWindowPosition()
            try expect(app.window?.frame.size == windowSize, "Repositioning must restore the full hosting canvas")
            try expect(app.window?.frame.maxY == a.frame.maxY && app.window?.frame.midX == a.frame.midX,
                       "Restored hosting canvas must remain top-centered")
        case "orphan-window":
            let primary = app.window!
            let orphan = BoringNotchSkyLightWindow()
            NSApp.windows.append(orphan)
            NotchSpaceManager.shared.notchSpace.windows.insert(orphan)
            app.adjustWindowPosition()
            try expect(orphan.closed && !primary.closed && app.window === primary,
                       "Orphaned notch must close without replacing the selected window")
            try expect(!NotchSpaceManager.shared.notchSpace.windows.contains(orphan),
                       "Orphaned notch must be removed from Space tracking")
            Defaults[.showOnAllDisplays] = true
            Defaults[.displayPlacementMode] = .all
            NSScreen.screens = [a, b]
            app.adjustWindowPosition()
            try expect(primary.closed && app.window == nil && app.windows.count == 2,
                       "Switching to all displays must retire the former single window")
            let formerMulti = Array(app.windows.values)
            Defaults[.showOnAllDisplays] = false
            Defaults[.displayPlacementMode] = .specific
            app.adjustWindowPosition()
            try expect(app.windows.isEmpty && formerMulti.allSatisfy(\.closed),
                       "Switching back must retire every all-display window")
            try expect(app.window != nil && app.window?.closed == false,
                       "Single-display mode must have exactly one live notch")
        default:
            throw FixtureFailure(description: "Unknown scenario")
        }
    }
}
