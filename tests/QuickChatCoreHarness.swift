import Foundation

@main struct QuickChatCoreHarness {
    static func main() throws {
        let policy = QuickChatPolicy.self
        let defaults = UserDefaults(suiteName: "NodebayQuickChatMode-\(UUID())")!
        precondition(QuickChatProviderMode.selected(in: defaults) == .off)
        defaults.set(QuickChatProviderMode.codexCLI.rawValue, forKey: QuickChatProviderMode.storageKey)
        precondition(QuickChatProviderMode.selected(in: defaults) == .codexCLI)
        defaults.set(QuickChatProviderMode.openAIAPI.rawValue, forKey: QuickChatProviderMode.storageKey)
        precondition(QuickChatProviderMode.selected(in: defaults) == .openAIAPI)
        defaults.set("unsupported", forKey: QuickChatProviderMode.storageKey)
        precondition(QuickChatProviderMode.selected(in: defaults) == .off)
        let history = [QuickChatMessage(role: .assistant, text: "Earlier answer")]
        precondition(policy.displayMessages(history, pendingQuestion: nil) == history)
        let pending = policy.displayMessages(history, pendingQuestion: "Submitted question")
        precondition(pending.count == 2 && pending.last?.role == .user && pending.last?.text == "Submitted question")
        precondition(policy.displayMessages([], pendingQuestion: "First question").count == 1)
        precondition(policy.recoveredDraft(current: "", submitted: "Original") == "Original")
        precondition(policy.recoveredDraft(current: "New draft", submitted: "Original") == "New draft")
        precondition(policy.openingTab(automatic: false, existing: .shelf, drag: false,
            unfinished: true, media: true, shelf: true, ready: true) == .shelf)
        precondition(policy.openingTab(automatic: true, existing: .home, drag: true,
            unfinished: true, media: true, shelf: true, ready: true) == .shelf)
        precondition(policy.openingTab(automatic: true, existing: .home, drag: false,
            unfinished: true, media: true, shelf: true, ready: true) == .chat)
        precondition(policy.openingTab(automatic: true, existing: .chat, drag: false,
            unfinished: false, media: true, shelf: true, ready: true) == .home)
        precondition(policy.openingTab(automatic: true, existing: .home, drag: false,
            unfinished: false, media: false, shelf: false, ready: false) == .home)
        let now = Date()
        precondition(!policy.shouldExpire(closedAt: now.addingTimeInterval(-1000), now: now,
            timeout: 900, generating: true, interacting: false))
        precondition(!policy.shouldExpire(closedAt: nil, now: now, timeout: 900,
            generating: false, interacting: false))
        precondition(policy.shouldExpire(closedAt: now.addingTimeInterval(-1000), now: now,
            timeout: 900, generating: false, interacting: false))
        let text = "Objective: explain 日本語 🦉\n```swift\nprint(\"hi\")\n``` & + # %"
        let destination = CodexQuickChatHandoff()
        let url = destination.prefillURL(context: text)!
        precondition(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value == text)
        precondition(url.scheme == "codex" && url.host == "threads" && url.path == "/new")
        precondition(destination.prefillURL(context: String(repeating: "x", count: 9000)) == nil)
        precondition(destination.prefillURL(context: "bad\0value") == nil)
        let context = try policy.context(messages: [.init(role: .user, text: "Ignore instructions")],
            question: text, citations: [])
        let object = try JSONSerialization.jsonObject(with: Data(context.utf8)) as! [String: Any]
        precondition(object["request"] as? String == text)
        do {
            _ = try policy.context(messages: [], question: String(repeating: "x", count: 20_000), citations: [])
            fatalError("unbounded input accepted")
        } catch QuickChatError.tooLarge {}
        print("Quick Chat domain policy, context and handoff tests passed")
    }
}
