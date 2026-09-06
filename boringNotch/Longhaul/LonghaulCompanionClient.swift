import AppKit
import Combine
import Foundation

struct LonghaulAutomaticChange {
    let enabled: Bool
    let serverInstance: String
    let afterRevision: Int
    let deadline: TimeInterval

    func isConfirmed(by snapshot: LonghaulCompanionSnapshot) -> Bool {
        snapshot.instanceID == serverInstance && snapshot.revision > afterRevision && snapshot.enabled == enabled
    }
}

@MainActor
final class LonghaulCompanionClient: ObservableObject {
    static let shared = LonghaulCompanionClient()
    static let appID = "space.exlumina.longhaul"
    static let controlSurfaceKey = "nodebay.longhaul.controlSurface"
    @Published private(set) var controlSurface: LonghaulControlSurface
    var showsNotchControl: Bool { controlSurface == .nodebay }
    @Published private(set) var state: LonghaulConnectionState = .notInstalled
    @Published private(set) var snapshot: LonghaulCompanionSnapshot?
    @Published private(set) var message = "Longhaul is an optional companion for automatic job protection."
    @Published private(set) var busy = false
    @Published private(set) var automaticChange: LonghaulAutomaticChange?
    @Published private(set) var automaticControlIssue: String?
    @Published private(set) var appURL: URL?
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "nodebay.longhaul.notifications") }
    }
    private var cursor = LonghaulSnapshotCursor()
    private var ledger: LonghaulAlertLedger
    private var serverInstance: String?
    private var task: Task<Void, Never>?
    private var polling = false
    private var failures = 0
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let transport: (Data) async throws -> Data
    private let resolveApplication: () -> URL?
    private let monotonicNow: () -> TimeInterval
    private let persistControlSurface: (LonghaulControlSurface) -> Void

    private init() {
        let defaults = UserDefaults.standard
        controlSurface = Self.restoreControlSurface(from: defaults)
        persistControlSurface = Self.surfacePersistence(in: defaults)
        notificationsEnabled = defaults.object(forKey: "nodebay.longhaul.notifications") as? Bool ?? true
        ledger = .init(delivered: defaults.stringArray(forKey: "nodebay.longhaul.deliveredAlerts") ?? [])
        transport = LonghaulHelperTransport.exchange
        resolveApplication = { Self.resolveAppURL { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.appID) } }
        monotonicNow = { ProcessInfo.processInfo.systemUptime }
    }

    /// Isolated protocol fixtures supply responses and time without XPC or app launches.
    init(testingTransport: @escaping (Data) async throws -> Data, testingAppURL: URL?,
         testingClock: @escaping () -> TimeInterval, testingDefaults: UserDefaults? = nil) {
        controlSurface = Self.restoreControlSurface(from: testingDefaults)
        persistControlSurface = Self.surfacePersistence(in: testingDefaults)
        notificationsEnabled = false; ledger = .init()
        transport = testingTransport; resolveApplication = { testingAppURL }; monotonicNow = testingClock
    }

    private static func restoreControlSurface(from defaults: UserDefaults?) -> LonghaulControlSurface {
        defaults?.string(forKey: controlSurfaceKey).flatMap(LonghaulControlSurface.init(rawValue:)) ?? .nodebay
    }

    private static func surfacePersistence(in defaults: UserDefaults?) -> (LonghaulControlSurface) -> Void {
        { surface in
            if defaults?.string(forKey: controlSurfaceKey) != surface.rawValue {
                defaults?.set(surface.rawValue, forKey: controlSurfaceKey)
            }
        }
    }

    var controlsBusy: Bool { busy || automaticChange != nil }
    var canToggleAutomaticProtection: Bool { state == .connected && snapshot != nil && !controlsBusy }
    var automaticProtectionStatus: String {
        if let change = automaticChange { return change.enabled ? "Turning on automatic protection" : "Pausing automatic protection" }
        switch state {
        case .connected: return snapshot?.enabled == true ? "Automatic protection on" : "Automatic protection off"
        case .available: return "Not connected to Longhaul"
        case .notInstalled: return "Longhaul is not installed"
        case .needsAttention: return "Automatic protection status unavailable"
        }
    }
    var automaticActionTitle: String { snapshot?.enabled == true ? "Pause Automatic Protection" : "Resume Automatic Protection" }
    func toggleAutomaticProtection() {
        guard canToggleAutomaticProtection, let snapshot else { return }
        control(snapshot.enabled ? "pause" : "resume")
    }

    func start() {
        guard task == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let delay = self.state == .connected ? 3.0 : min(60.0, 10.0 * Double(max(1, self.failures)))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard !polling, !busy else { return }
        polling = true
        defer { polling = false }
        appURL = resolveApplication()
        guard appURL != nil else {
            state = .notInstalled; snapshot = nil; serverInstance = nil; automaticChange = nil
            message = "Install Longhaul separately, then return here to connect. No public installer is configured yet."
            return
        }
        if let change = automaticChange, monotonicNow() >= change.deadline {
            automaticChange = nil; state = .needsAttention; snapshot = nil; serverInstance = nil
            automaticControlIssue = "Longhaul did not confirm the change. Open Longhaul to check automatic protection."
            message = automaticControlIssue!
            return
        }
        let epoch = generation
        do {
            let response = try await exchange(.init(op: "hello"))
            guard epoch == generation else { return }
            apply(response)
            failures = response.state == .needsAttention ? min(6, failures + 1) : 0
            if response.state == .available && !UserDefaults.standard.bool(forKey: "nodebay.longhaul.connectionOfferShown") {
                _ = BoringViewCoordinator.shared.queueLonghaulNotice(.init(id: "nodebay-longhaul-connection-offer-v1", title: "Connect with Nodebay", body: "Open Longhaul to enable the optional Nodebay connection. Both apps remain independent."))
            }
            await deliverAlerts()
        } catch {
            guard epoch == generation else { return }
            failures = min(6, failures + 1)
            if automaticChange != nil { automaticControlIssue = "The connection was lost before automatic protection was confirmed. Open Longhaul to check its state." }
            state = .needsAttention; snapshot = nil; serverInstance = nil; automaticChange = nil
            message = automaticControlIssue ?? error.localizedDescription
        }
    }

    func control(_ operation: String, minutes: Int? = nil) {
        guard !controlsBusy, ["connect", "disconnect", "pause", "resume", "keepAwake"].contains(operation),
              operation == "connect" || state == .connected,
              operation != "keepAwake" || [30, 60, 240].contains(minutes ?? 0) else { return }
        if operation == "pause" || operation == "resume" {
            guard let snapshot, let serverInstance, snapshot.instanceID == serverInstance else { return }
            automaticChange = .init(enabled: operation == "resume", serverInstance: serverInstance,
                                    afterRevision: snapshot.revision, deadline: monotonicNow() + 15)
        }
        automaticControlIssue = nil
        busy = true; generation += 1
        message = operation == "connect" ? "Requesting connection. Longhaul may ask you to approve Nodebay." : "Request sent; waiting for Longhaul."
        Task {
            do {
                if serverInstance == nil {
                    let hello = try await exchange(.init(op: "hello"))
                    serverInstance = hello.serverInstance
                }
                let response = try await exchange(.init(op: operation, serverInstance: serverInstance, minutes: minutes))
                apply(response)
            } catch {
                if automaticChange != nil { automaticControlIssue = "Longhaul did not confirm the change. Open Longhaul to check automatic protection." }
                state = .needsAttention; snapshot = nil; serverInstance = nil; automaticChange = nil
                message = automaticControlIssue ?? error.localizedDescription
            }
            busy = false
            await refresh()
        }
    }

    func openLonghaul() {
        // Resolve again at the user's action, since installation may have changed
        // since the last poll and Launch Services may remember a test candidate.
        appURL = resolveApplication()
        guard let url = appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func resolveAppURL(installedURL: URL = URL(fileURLWithPath: "/Applications/Longhaul.app", isDirectory: true),
                              fallback: () -> URL?) -> URL? {
        if Bundle(url: installedURL)?.bundleIdentifier == appID { return installedURL }
        guard let candidate = fallback(), Bundle(url: candidate)?.bundleIdentifier == appID else { return nil }
        return candidate
    }

    private func apply(_ response: LonghaulCompanionResponse) {
        let connectionChanged = automaticChange.map { $0.serverInstance != response.serverInstance } ?? false
        serverInstance = response.serverInstance
        if let value = response.snapshot {
            guard cursor.accept(value) else { return }
            snapshot = value
            controlSurface = value.resolvedControlSurface
            persistControlSurface(controlSurface)
        } else { snapshot = nil }
        state = response.state
        message = response.message ?? response.snapshot?.reason ?? "Open Longhaul to finish setting up this connection."
        if connectionChanged {
            automaticChange = nil
            automaticControlIssue = "The connection restarted before the change was confirmed. Check automatic protection in Longhaul."
        } else if response.state != .connected {
            if automaticChange != nil { automaticControlIssue = "The connection is unavailable; the automatic protection change was not confirmed." }
            automaticChange = nil
        } else if let change = automaticChange {
            if let snapshot, change.isConfirmed(by: snapshot) { automaticChange = nil; automaticControlIssue = nil }
            else { message = automaticProtectionStatus + "; waiting for Longhaul to confirm." }
        }
        if let issue = automaticControlIssue { message = issue }
    }

    private func deliverAlerts() async {
        guard state == .connected, notificationsEnabled, let snapshot else { return }
        for alert in snapshot.alerts {
            if ledger.contains(alert.id) {
                // Retry a lost acknowledgement without displaying the notice twice.
                _ = try? await exchange(.init(op: "ackAlert", serverInstance: serverInstance, alertID: alert.id))
                continue
            }
            // The coordinator can decline while busy. Longhaul keeps its fallback
            // responsibility until a notice is actually queued on a visible notch.
            guard BoringViewCoordinator.shared.queueLonghaulNotice(alert) else { continue }
        }
    }

    func noticeWasPresented(_ id: String) async {
        if id == "nodebay-longhaul-connection-offer-v1" {
            UserDefaults.standard.set(true, forKey: "nodebay.longhaul.connectionOfferShown")
            return
        }
        guard state == .connected, !ledger.contains(id), snapshot?.alerts.contains(where: { $0.id == id }) == true else { return }
        ledger.record(id)
        UserDefaults.standard.set(ledger.delivered, forKey: "nodebay.longhaul.deliveredAlerts")
        _ = try? await exchange(.init(op: "ackAlert", serverInstance: serverInstance, alertID: id))
    }


    private func exchange(_ request: LonghaulCompanionRequest) async throws -> LonghaulCompanionResponse {
        var request = request
        request.capabilities = ["hello", "status"].contains(request.op) ? ["control-surface-v1"] : nil
        let data = try JSONEncoder().encode(request)
        let result = try await transport(data)
        return try LonghaulCompanionResponse.decode(result)
    }
}

/// Dedicated connection so a companion timeout cannot invalidate an unrelated
/// conversion, media HUD callback, or Quick Chat request using the shared helper.
private enum LonghaulHelperTransport {
    static func exchange(_ data: Data) async throws -> Data {
        guard data.count <= 65_536 else { throw LonghaulCompanionError.invalidResponse }
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
            connection.remoteObjectInterface = NSXPCInterface(with: BoringNotchXPCHelperProtocol.self)
            connection.setCodeSigningRequirement("anchor apple generic and identifier \"theboringteam.boringnotch.BoringNotchXPCHelper\" and certificate leaf[subject.OU] = \"HZWY8HT54D\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists")
            let gate = LonghaulReplyGate(connection: connection, continuation: continuation)
            connection.invalidationHandler = { gate.finish(.failure(LonghaulCompanionError.unavailable)) }
            connection.interruptionHandler = { gate.finish(.failure(LonghaulCompanionError.unavailable)) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in gate.finish(.failure(LonghaulCompanionError.unavailable)) }) as? BoringNotchXPCHelperProtocol else {
                gate.finish(.failure(LonghaulCompanionError.unavailable)); return
            }
            proxy.longhaulExchange(data) { response in
                guard connection.effectiveUserIdentifier == geteuid(), response.count <= 65_536 else {
                    gate.finish(.failure(LonghaulCompanionError.invalidResponse)); return
                }
                gate.finish(.success(response))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { gate.finish(.failure(LonghaulCompanionError.timeout)) }
        }
    }
}

private final class LonghaulReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private let connection: NSXPCConnection
    init(connection: NSXPCConnection, continuation: CheckedContinuation<Data, Error>) {
        self.connection = connection; self.continuation = continuation
    }
    func finish(_ result: Result<Data, Error>) {
        let value = lock.withLock { let value = continuation; continuation = nil; return value }
        guard let value else { return }
        connection.invalidationHandler = nil; connection.interruptionHandler = nil
        connection.invalidate()
        value.resume(with: result)
    }
}
