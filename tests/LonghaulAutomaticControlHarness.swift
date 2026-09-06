import Foundation

/// Standalone client dependency. No notices, app preference changes or app activation.
@MainActor final class BoringViewCoordinator {
    static let shared = BoringViewCoordinator()
    func queueLonghaulNotice(_ alert: LonghaulCompanionAlert) -> Bool { false }
}

@MainActor private final class ScriptedLonghaul {
    var now = 100.0
    var instance = "server-first"
    var revision = 1
    var enabled = true
    var protecting = false
    var controlSurface: String?
    var suspendNextHello = false
    var suspendedResponse: Data?
    var suspended: CheckedContinuation<Data, Error>?
    var state: LonghaulConnectionState = .connected
    var rejectControl = false
    var rejectAll = false
    var applyImmediately = false
    var requests: [LonghaulCompanionRequest] = []
    var mutations: [String] { requests.map(\.op).filter { !["hello", "status"].contains($0) } }
    func exchange(_ data: Data) async throws -> Data {
        let request = try JSONDecoder().decode(LonghaulCompanionRequest.self, from: data)
        requests.append(request)
        if rejectAll || (rejectControl && ["pause", "resume"].contains(request.op)) { throw LonghaulCompanionError.unavailable }
        if applyImmediately && ["pause", "resume"].contains(request.op) { enabled = request.op == "resume"; revision += 1 }
        let snapshot = LonghaulCompanionSnapshot(instanceID: instance, revision: revision, mode: "ready", reason: "Fixture state",
            protecting: protecting, enabled: enabled, jobCount: 0, jobs: [], batteryStage: "normal", batteryPercent: 80,
            checkpointSummary: nil, alerts: [], controlSurface: controlSurface)
        let response = try JSONEncoder().encode(LonghaulCompanionResponse(version: 1, serverInstance: instance, state: state,
            message: ["pause", "resume"].contains(request.op) ? "Request queued; awaiting Longhaul." : nil,
            snapshot: state == .connected ? snapshot : nil))
        if suspendNextHello && request.op == "hello" {
            suspendNextHello = false; suspendedResponse = response
            return try await withCheckedThrowingContinuation { suspended = $0 }
        }
        return response
    }
    func resumeHello() {
        guard let suspended, let response = suspendedResponse else { fatalError("No suspended fixture") }
        self.suspended = nil; suspendedResponse = nil; suspended.resume(returning: response)
    }
    func client(installed: Bool = true, defaults: UserDefaults? = nil) -> LonghaulCompanionClient {
        LonghaulCompanionClient(testingTransport: exchange,
            testingAppURL: installed ? URL(fileURLWithPath: "/fixture/Longhaul.app") : nil,
            testingClock: { self.now }, testingDefaults: defaults)
    }
}

@main @MainActor struct LonghaulAutomaticControlHarness {
    static func main() async {
        var checks = 0
        func check(_ value: Bool, _ reason: String) { guard value else { fatalError(reason) }; checks += 1 }
        func settle(_ client: LonghaulCompanionClient) async {
            for _ in 0..<100 {
                if !client.busy { return }
                await Task.yield()
            }
            fatalError("Scripted request did not finish")
        }

        let server = ScriptedLonghaul(), client = ScriptedLonghaul().client(installed: false)
        await client.refresh(); client.toggleAutomaticProtection()
        check(client.state == .notInstalled && !client.canToggleAutomaticProtection, "Not installed never sends a toggle")
        let connected = server.client()
        await connected.refresh()
        check(connected.canToggleAutomaticProtection && connected.snapshot?.enabled == true && connected.snapshot?.protecting == false,
              "Automation may be on with no current power assertion")
        connected.toggleAutomaticProtection(); connected.toggleAutomaticProtection()
        await settle(connected)
        check(server.mutations == ["pause"], "Tap uses acknowledged enabled, not protecting, and suppresses duplicate clicks")
        check(connected.automaticChange?.enabled == false && !connected.canToggleAutomaticProtection, "Queued response stays pending")
        check(connected.snapshot?.enabled == true, "No optimistic off state")
        connected.toggleAutomaticProtection()
        check(server.mutations == ["pause"], "Repeated tap remains blocked after request transport completes")
        server.revision = 2
        await connected.refresh()
        check(connected.automaticChange != nil, "New revision with old enabled state is not confirmation")
        server.revision = 0; server.enabled = false
        await connected.refresh()
        check(connected.snapshot?.enabled == true && connected.automaticChange != nil, "Stale snapshot cannot flip the button")
        server.revision = 3
        await connected.refresh()
        check(connected.snapshot?.enabled == false && connected.automaticChange == nil && connected.canToggleAutomaticProtection,
              "New acknowledged off state finishes pause")
        check(connected.automaticProtectionStatus == "Automatic protection off", "Off status is explicit")
        connected.toggleAutomaticProtection(); await settle(connected)
        check(server.mutations == ["pause", "resume"] && connected.snapshot?.enabled == false, "Next click resumes without optimistic on state")
        server.enabled = true; server.revision = 4
        await connected.refresh()
        check(connected.automaticChange == nil && connected.snapshot?.enabled == true, "Resume confirms only from newer enabled snapshot")
        check(server.requests.allSatisfy { $0.minutes == nil && $0.op != "keepAwake" }, "Automatic toggle never requests timed keep awake")
        check(server.requests.filter { ["pause", "resume"].contains($0.op) }.allSatisfy { $0.serverInstance == "server-first" },
              "Controls carry acknowledged server instance")

        let unpaired = ScriptedLonghaul(); unpaired.state = .available
        let unpairedClient = unpaired.client(); await unpairedClient.refresh(); unpairedClient.toggleAutomaticProtection()
        check(unpairedClient.automaticProtectionStatus == "Not connected to Longhaul" && unpaired.mutations.isEmpty,
              "Unpaired state never toggles or auto-connects")
        let unavailable = ScriptedLonghaul(); unavailable.rejectAll = true
        let unavailableClient = unavailable.client(); await unavailableClient.refresh(); unavailableClient.toggleAutomaticProtection()
        check(unavailableClient.state == .needsAttention && unavailable.mutations.isEmpty, "Unavailable connection never guesses a toggle")

        let delayed = ScriptedLonghaul(), delayedClient: LonghaulCompanionClient
        delayedClient = delayed.client(); await delayedClient.refresh()
        delayedClient.toggleAutomaticProtection(); await settle(delayedClient)
        delayed.now += 16
        await delayedClient.refresh()
        check(delayedClient.automaticChange == nil && delayedClient.state == .needsAttention && delayedClient.snapshot == nil,
              "Unconfirmed request has a bounded pending lifetime")
        check(delayedClient.automaticControlIssue != nil, "Timeout remains an explicit unconfirmed change")
        await delayedClient.refresh()
        check(delayedClient.snapshot?.enabled == true && delayedClient.automaticControlIssue != nil && delayed.mutations == ["pause"],
              "Reconnect shows current state and retains failure without auto-retrying mutation")

        let restarted = ScriptedLonghaul(), restartedClient: LonghaulCompanionClient
        restartedClient = restarted.client(); await restartedClient.refresh()
        restartedClient.toggleAutomaticProtection(); await settle(restartedClient)
        restarted.instance = "server-second"; restarted.revision = 0; restarted.enabled = false
        await restartedClient.refresh()
        check(restartedClient.automaticChange == nil && restartedClient.message.contains("restarted"), "Restart ends pending without pretending command confirmation")
        check(restarted.mutations == ["pause"], "Restart does not reissue old control")

        let failed = ScriptedLonghaul(), failedClient: LonghaulCompanionClient
        failedClient = failed.client(); await failedClient.refresh(); failed.rejectControl = true
        failedClient.toggleAutomaticProtection(); await settle(failedClient)
        check(failedClient.automaticChange == nil && failedClient.snapshot?.enabled == true && failedClient.automaticControlIssue != nil,
              "Failed command retains actual state and an honest error after healthy status poll")

        let revoked = ScriptedLonghaul(), revokedClient: LonghaulCompanionClient
        revokedClient = revoked.client(); await revokedClient.refresh()
        revokedClient.toggleAutomaticProtection(); await settle(revokedClient)
        revoked.state = .available
        await revokedClient.refresh()
        check(revokedClient.automaticChange == nil && revokedClient.snapshot == nil && !revokedClient.canToggleAutomaticProtection,
              "Revocation clears pending and private status")

        let immediate = ScriptedLonghaul(); immediate.applyImmediately = true
        let immediateClient = immediate.client(); await immediateClient.refresh()
        immediateClient.toggleAutomaticProtection(); await settle(immediateClient)
        check(immediateClient.automaticChange == nil && immediateClient.snapshot?.enabled == false,
              "A command response can confirm when it already contains the newer applied snapshot")
        check(server.requests.filter { ["hello", "status"].contains($0.op) }.allSatisfy { $0.capabilities == ["control-surface-v1"] },
              "Read-only polls advertise exactly the supported route capability")
        check(server.requests.filter { !["hello", "status"].contains($0.op) }.allSatisfy { $0.capabilities == nil },
              "Control messages never include capability negotiation")

        let suiteName = "Nodebay.LonghaulVisibilityFixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let routeKey = LonghaulCompanionClient.controlSurfaceKey
        let routing = ScriptedLonghaul()
        let routed = routing.client(defaults: defaults)
        check(routed.showsNotchControl && defaults.object(forKey: routeKey) == nil, "Fresh state shows legacy icon without persisting an unaccepted route")
        routing.controlSurface = "menuBar"; await routed.refresh()
        check(!routed.showsNotchControl && defaults.string(forKey: routeKey) == "menuBar", "Accepted menu bar snapshot hides and persists the route")
        let restored = routing.client(installed: false, defaults: defaults)
        check(!restored.showsNotchControl, "Cached menu bar route hides icon immediately on client initialization")
        await restored.refresh()
        check(!restored.showsNotchControl && restored.state == .notInstalled, "Missing companion preserves last accepted visibility")
        routing.controlSurface = "nodebay"; routing.revision = 0; await routed.refresh()
        check(!routed.showsNotchControl && defaults.string(forKey: routeKey) == "menuBar", "Older snapshot cannot overwrite persisted visibility")
        routing.revision = 1; await routed.refresh()
        check(!routed.showsNotchControl, "Conflicting same-revision route is rejected")
        routing.revision = 2; routing.controlSurface = "invalid"; await routed.refresh()
        check(!routed.showsNotchControl && routed.state == .needsAttention && defaults.string(forKey: routeKey) == "menuBar", "Invalid route preserves visibility through error cleanup")
        routing.controlSurface = "nodebay"; routing.revision = 0; await routed.refresh()
        check(!routed.showsNotchControl, "An error cannot reset the accepted cursor and admit an older route")
        routing.state = .available; await routed.refresh()
        check(!routed.showsNotchControl && routed.snapshot == nil, "Unpairing and nil snapshot preserve cached visibility")
        routing.instance = "server-restarted"; routing.state = .needsAttention; await routed.refresh()
        check(!routed.showsNotchControl, "Restart without a valid connected snapshot preserves visibility")
        routing.state = .connected; routing.controlSurface = nil; await routed.refresh()
        check(routed.showsNotchControl && defaults.string(forKey: routeKey) == "nodebay", "Accepted legacy snapshot on new instance restores and persists Nodebay route")
        routing.controlSurface = "menuBar"; routing.revision = 1; await routed.refresh()
        routing.rejectAll = true; await routed.refresh()
        check(!routed.showsNotchControl, "Transport loss preserves latest accepted menu bar route")
        routing.rejectAll = false; routing.controlSurface = "nodebay"; routing.revision = 0; await routed.refresh()
        check(!routed.showsNotchControl, "Lower revision stays stale after reconnect")
        routing.controlSurface = nil; routing.revision = 2; await routed.refresh()
        check(routed.showsNotchControl, "Newer legacy snapshot in the same epoch restores Nodebay route")
        check(routing.mutations.isEmpty && !routed.notificationsEnabled, "Visibility negotiation changes no automation or notice preference")
        defaults.set("unsupported", forKey: routeKey)
        let invalidCache = routing.client(defaults: defaults)
        check(invalidCache.showsNotchControl && defaults.string(forKey: routeKey) == "unsupported", "Invalid persisted value falls back safely without an unaccepted write")
        await invalidCache.refresh()
        check(defaults.string(forKey: routeKey) == "nodebay", "Accepted snapshot repairs invalid persisted route")

        let racing = ScriptedLonghaul(), racingClient: LonghaulCompanionClient
        racingClient = racing.client(); await racingClient.refresh()
        racing.revision = 2; racing.controlSurface = "menuBar"; racing.suspendNextHello = true
        let stalePoll = Task { await racingClient.refresh() }
        while racing.suspended == nil { await Task.yield() }
        racing.revision = 3; racing.controlSurface = "nodebay"
        racingClient.toggleAutomaticProtection(); await settle(racingClient)
        racing.resumeHello(); await stalePoll.value
        check(racingClient.showsNotchControl && racingClient.snapshot?.revision == 3,
              "Poll superseded by a control response cannot restore stale visibility")
        print("Longhaul automatic control: \(checks) checks passed; no apps launched")
    }
}
