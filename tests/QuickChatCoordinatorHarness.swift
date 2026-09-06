import Foundation

private actor SyntheticChatProvider: QuickChatProvider {
    var ready = true
    var pending: [UUID: CheckedContinuation<String, Error>] = [:]
    var requests: [(UUID, Bool)] = []
    var cancellations: [UUID] = []
    func status() async -> QuickChatProviderStatus {
        .init(availability: ready ? .ready : .missing, version: "synthetic", explanation: "synthetic")
    }
    func answer(requestID: UUID, context: String, thinkDeeper: Bool) async throws -> String {
        requests.append((requestID, thinkDeeper))
        return try await withCheckedThrowingContinuation { pending[requestID] = $0 }
    }
    func cancel(requestID: UUID) async { cancellations.append(requestID) }
    func resolve(_ id: UUID, error: Bool = false) {
        let continuation = pending.removeValue(forKey: id)
        if error { continuation?.resume(throwing: QuickChatError.failed) }
        else { continuation?.resume(returning: "Synthetic answer") }
    }
    func setUnavailable() { ready = false }
}

private actor SyntheticStatusProvider: QuickChatProvider {
    let version: String
    var validation: CheckedContinuation<QuickChatProviderStatus, Never>?
    var statusReply: CheckedContinuation<QuickChatProviderStatus, Never>?
    var delayStatus = false
    init(_ version: String) { self.version = version }
    func status() async -> QuickChatProviderStatus {
        if delayStatus { return await withCheckedContinuation { statusReply = $0 } }
        return .init(availability: .ready, version: version, explanation: "Synthetic ready")
    }
    func validate() async -> QuickChatProviderStatus {
        await withCheckedContinuation { validation = $0 }
    }
    func resolveValidation() {
        validation?.resume(returning: .init(availability: .ready, version: version, explanation: "Synthetic validated"))
        validation = nil
    }
    func delayNextStatus() { delayStatus = true }
    func resolveStatus() {
        statusReply?.resume(returning: .init(availability: .ready, version: version, explanation: "Synthetic late status"))
        statusReply = nil; delayStatus = false
    }
    func answer(requestID: UUID, context: String, thinkDeeper: Bool) async throws -> String { "Synthetic answer" }
    func cancel(requestID: UUID) async {}
}

@main struct QuickChatCoordinatorHarness {
    @MainActor static func main() async throws {
        func settle() async { try? await Task.sleep(for: .milliseconds(40)) }
        let provider = SyntheticChatProvider()
        var clock = Date(timeIntervalSince1970: 1_000)
        let chat = QuickChatCoordinator(provider: provider, defaults: UserDefaults(suiteName: "NodebaySynthetic-\(UUID())")!, now: { clock })
        await chat.rescan()
        chat.draft = "Synthetic first question"
        chat.send()
        precondition(chat.generating && chat.pendingQuestion != nil && chat.draft.isEmpty)
        await settle()
        let first = await provider.requests.last!
        precondition(!first.1)
        chat.draft = "Next draft"
        await provider.resolve(first.0)
        await settle()
        precondition(chat.messages.count == 2 && chat.draft == "Next draft" && !chat.generating)

        chat.screen("built-in", open: true); chat.screen("external", open: true)
        chat.screen("built-in", open: false); chat.screen("external", open: false)
        precondition(chat.messages.count == 2 && chat.draft == "Next draft")
        clock.addTimeInterval(179 * 60)
        chat.expireIfNeeded()
        precondition(chat.messages.count == 2)
        chat.screen("external", open: true) // Real re-entry renews activity.
        clock.addTimeInterval(2 * 60)
        chat.expireIfNeeded()
        precondition(chat.messages.count == 2)

        chat.thinkDeeper = true
        chat.send()
        precondition(chat.activeThinkDeeper && !chat.thinkDeeper)
        await settle()
        let deeper = await provider.requests.last!
        precondition(deeper.1)
        chat.screen("external", open: false)
        clock.addTimeInterval(4 * 3600)
        chat.expireIfNeeded()
        precondition(chat.generating && chat.messages.count == 2)
        chat.stop()
        precondition(chat.draft == "Next draft" && !chat.generating)
        await provider.resolve(deeper.0)
        await settle()
        precondition(chat.messages.count == 2) // Late cancelled answer ignored.

        chat.send() // Retry restored draft, normal reasoning.
        await settle()
        let retry = await provider.requests.last!
        chat.draft = "Preserve newer input"
        await provider.resolve(retry.0, error: true)
        await settle()
        precondition(chat.draft == "Preserve newer input" && chat.error != nil)

        chat.send()
        await settle()
        let stale = await provider.requests.last!
        chat.newChat()
        await provider.resolve(stale.0)
        await settle()
        precondition(chat.messages.isEmpty && chat.draft.isEmpty && chat.error == nil)

        chat.draft = "Temporary draft"
        chat.userActivity()
        let interactionA = UUID(), interactionB = UUID()
        chat.interaction(true, source: interactionA); chat.interaction(true, source: interactionB)
        chat.interaction(false, source: interactionA)
        clock.addTimeInterval(4 * 3600)
        chat.expireIfNeeded()
        precondition(chat.interacting && chat.draft == "Temporary draft")
        chat.interaction(false, source: interactionB)
        chat.expireIfNeeded()
        precondition(!chat.interacting && chat.draft.isEmpty)
        precondition(QuickChatPolicy.inactivityMinutes(stored: nil) == 180)
        precondition(QuickChatPolicy.inactivityMinutes(stored: 15) == 15)
        precondition(QuickChatPolicy.inactivityMinutes(stored: 60) == 60)
        precondition(QuickChatPolicy.inactivityMinutes(stored: .nan) == 180)
        await provider.setUnavailable()
        await chat.rescan()
        chat.draft = "Provider unavailable"
        chat.send()
        precondition(!chat.generating && chat.draft == "Provider unavailable")

        let preferences = UserDefaults(suiteName: "NodebaySyntheticSettings-\(UUID())")!
        preferences.set(QuickChatProviderMode.openAIAPI.rawValue, forKey: QuickChatProviderMode.storageKey)
        var providers: [String: SyntheticStatusProvider] = [:]
        let settings = QuickChatCoordinator(defaults: preferences, providerFactory: { _, defaults in
            let model = defaults.string(forKey: "nodebay.quickChat.apiModel") ?? QuickChatProviderMode.defaultAPIModel
            let result = SyntheticStatusProvider(model)
            providers[model] = result
            return result
        })
        await settle()
        let original = providers[QuickChatProviderMode.defaultAPIModel]!
        let oldValidation = Task { await settings.validateProvider() }
        await settle()
        precondition(settings.validating)
        settings.selectMode(.off)
        precondition(!settings.validating && settings.status.availability == .disabled)
        await original.resolveValidation()
        await oldValidation.value
        precondition(settings.mode == .off && settings.status.availability == .disabled)

        settings.selectMode(.openAIAPI)
        await settle()
        preferences.set("new-model-without-return", forKey: "nodebay.quickChat.apiModel")
        let newValidation = Task { await settings.validateProvider() }
        await settle()
        let updated = providers["new-model-without-return"]!
        precondition(settings.validating)
        await updated.resolveValidation()
        await newValidation.value
        precondition(settings.status.version == "new-model-without-return")
        precondition(settings.status.explanation == "Synthetic validated")

        await updated.delayNextStatus()
        let staleRescan = Task { await settings.rescan() }
        await settle()
        settings.selectMode(.off)
        await updated.resolveStatus()
        await staleRescan.value
        precondition(settings.status.availability == .disabled)
        print("Synthetic coordinator cancellation, late reply, retry, new chat, draft and reasoning checks passed")
        print("Provider settings reject stale validation/rescan results and apply unsent model edits")
    }
}
