import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    @Published var automaticallyDownloadsUpdates = false
    @Published var lastUpdateCheckDate: Date?

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloadsUpdates)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastUpdateCheckDate)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var model: CheckForUpdatesViewModel
    @ObservedObject private var updates = SoftwareUpdateStore.shared
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.isConfigured || !model.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    @StateObject private var model: CheckForUpdatesViewModel
    @ObservedObject private var updates = SoftwareUpdateStore.shared
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Section("Software updates") {
            CheckForUpdatesView(updater: updater)
            Toggle("Automatically check for updates", isOn: Binding(
                get: { model.automaticallyChecksForUpdates },
                set: { updates.setAutomaticChecks($0) }
            ))
            .disabled(!updates.isConfigured)
            Toggle("Automatically download updates", isOn: Binding(
                get: { model.automaticallyDownloadsUpdates },
                set: { updates.setAutomaticDownloads($0) }
            ))
            .disabled(!updates.isConfigured || !model.automaticallyChecksForUpdates)
            Text("Updates come from Nodebay's signed release feed. Downloads install when you quit; restarting waits for active work and unfinished drafts.")
                .font(.callout).foregroundStyle(.secondary)
            if let date = model.lastUpdateCheckDate {
                LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let message = updates.status {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class SoftwareUpdateStore: ObservableObject {
    static let shared = SoftwareUpdateStore()
    static var updater: SPUUpdater? { shared.updater }
    @Published private(set) var isConfigured = false
    @Published private(set) var status: String?
    private(set) var updater: SPUUpdater?
    private var configuration: NodebayUpdateConfiguration?
    private var waitTimer: Timer?
    private var choiceAlertIsPresented = false
    private lazy var installGate = NodebayUpdateInstallGate(
        isBusy: { Self.hasActiveWork },
        flush: { ShelfStateViewModel.shared.flushSync() }
    )

    static var hasActiveWork: Bool {
        ShelfStateViewModel.shared.isLoading
            || !ShelfStateViewModel.shared.convertingItemIDs.isEmpty
            || DownloadCoordinator.shared.hasActiveTasks
            || STLRepairCoordinator.shared.isRunning
            || QuickNotesCoordinator.shared.isWorking
            || QuickChatCoordinator.shared.unfinished
            || QuickChatCoordinator.shared.validating
            || SharingStateManager.shared.preventNotchClose
            || MusicManager.shared.isResolvingCurrentMediaDownload
            || FeatureSetupCoordinator.shared.isInstalling
    }

    func configure(_ updater: SPUUpdater) {
        self.updater = updater
        configuration = NodebayUpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
        guard configuration != nil else {
            status = "In-app updates are unavailable because this build is missing its signed Nodebay update configuration."
            return
        }
        // A preference left by the original upstream app must never select its feed.
        updater.clearFeedURLFromUserDefaults()
        do {
            try updater.start()
            isConfigured = true
        } catch {
            status = "Nodebay could not start its updater. Download the current release from GitHub."
        }
    }

    var feedURLString: String? { configuration?.feedURL.absoluteString }
    var needsChoice: Bool { NodebayUpdatePreferences.needsChoice(in: .standard) }

    func recordChoice(automaticChecks: Bool, automaticDownloads: Bool) {
        guard isConfigured, let updater else { return }
        NodebayUpdatePreferences.recordChoice(in: .standard)
        updater.automaticallyDownloadsUpdates = automaticDownloads
        updater.automaticallyChecksForUpdates = automaticChecks
        status = nil
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isConfigured, let updater else { return }
        NodebayUpdatePreferences.recordChoice(in: .standard)
        updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard isConfigured, let updater else { return }
        NodebayUpdatePreferences.recordChoice(in: .standard)
        updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates() {
        guard isConfigured, let updater, updater.canCheckForUpdates else { return }
        status = nil
        updater.checkForUpdates()
    }

    func presentMigrationChoiceIfNeeded() {
        guard isConfigured, needsChoice, !choiceAlertIsPresented else { return }
        choiceAlertIsPresented = true
        defer { choiceAlertIsPresented = false }
        let alert = NSAlert()
        alert.messageText = "Keep Nodebay up to date?"
        alert.informativeText = "Nodebay now supports signed in-app updates. Choose automatic checks or keep checking manually. Updates install when you quit and wait for active work to finish."
        alert.addButton(withTitle: "Enable Automatic Updates")
        alert.addButton(withTitle: "Check Manually")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Download updates automatically"
        alert.suppressionButton?.state = .on
        NSApp.activate(ignoringOtherApps: true)
        let choice = alert.runModal()
        recordChoice(automaticChecks: choice == .alertFirstButtonReturn,
                     automaticDownloads: choice == .alertFirstButtonReturn && alert.suppressionButton?.state == .on)
    }

    func postponeInstallation(_ install: @escaping () -> Void) -> Bool {
        guard installGate.postpone(install) else { return false }
        status = "Update ready. Waiting for active work and unfinished drafts before restarting."
        waitTimer?.invalidate()
        waitTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.installGate.resumeIfIdle()
                if !self.installGate.isWaiting {
                    self.waitTimer?.invalidate()
                    self.waitTimer = nil
                    self.status = nil
                }
            }
        }
        return true
    }

    func cancelDeferredInstallation() {
        installGate.cancel()
        waitTimer?.invalidate()
        waitTimer = nil
    }

    func canTerminate() -> Bool {
        let canTerminate = installGate.canTerminate()
        if !canTerminate { status = "Finish or cancel current work and unfinished drafts before quitting or restarting Nodebay." }
        return canTerminate
    }

    func restartIfIdle() {
        guard canTerminate() else { showBusyNotice(); return }
        ApplicationRelauncher.restart()
    }

    func showBusyNotice() {
        let alert = NSAlert()
        alert.messageText = "Nodebay still has unfinished work"
        alert.informativeText = status ?? "Finish or cancel current work before restarting."
        alert.addButton(withTitle: "Keep Running")
        alert.runModal()
    }
}

@MainActor
final class BoringSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { SoftwareUpdateStore.shared.feedURLString }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try NodebayUpdateCheckPolicy.validate(
            isUserInitiated: updateCheck == .updates,
            isConfigured: SoftwareUpdateStore.shared.isConfigured,
            needsChoice: SoftwareUpdateStore.shared.needsChoice
        )
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        SoftwareUpdateStore.shared.postponeInstallation(installHandler)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        ShelfStateViewModel.shared.flushSync()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        SoftwareUpdateStore.shared.cancelDeferredInstallation()
    }
}
