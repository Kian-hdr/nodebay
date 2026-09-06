import Foundation

/// Provider-independent, memory-only chat values. Never Codable: transcripts
/// must not be accidentally included in preferences or restoration snapshots.
struct QuickChatMessage: Identifiable, Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    init(role: Role, text: String) { self.id = UUID(); self.role = role; self.text = text }
}

enum QuickChatAvailability: String, Sendable {
    case disabled, checking, ready, missing, incompatible, signedOut, expired, offline, rateLimited, failed
}

enum QuickChatProviderMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case codexCLI = "codex-cli"
    case openAIAPI = "openai-api"

    static let storageKey = "nodebay.quickChat.providerMode"
    static let defaultAPIModel = "gpt-5-mini"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .codexCLI: "Codex CLI"
        case .openAIAPI: "OpenAI API"
        }
    }

    static func selected(in defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: storageKey), let mode = Self(rawValue: raw) else {
            return .off
        }
        return mode
    }
}

struct QuickChatProviderStatus: Sendable, Equatable {
    var availability: QuickChatAvailability
    var version: String
    var explanation: String
}

protocol QuickChatProvider: Sendable {
    func status() async -> QuickChatProviderStatus
    func validate() async -> QuickChatProviderStatus
    func answer(requestID: UUID, context: String, thinkDeeper: Bool) async throws -> String
    func cancel(requestID: UUID) async
}

extension QuickChatProvider {
    func validate() async -> QuickChatProviderStatus { await status() }
}

struct QuickChatCitation: Identifiable, Sendable, Equatable {
    let id: String
    let relativePath: String
    let excerpt: String
    let modifiedAt: Date?
}

protocol QuickChatKnowledgeRetrieving: Sendable {
    func search(question: String) async throws -> [QuickChatCitation]
}

protocol QuickChatHandoffDestination {
    var name: String { get }
    func prefillURL(context: String) -> URL?
}

enum QuickChatError: String, Error, LocalizedError {
    case unavailable = "The selected AI provider is unavailable. Check AI & Quick Chat settings."
    case missingAPIKey = "Add an OpenAI API key in AI & Quick Chat settings."
    case expired = "Codex authorization needs attention. Your draft is still here."
    case failed = "Codex could not finish. Your draft is still here; try again."
    case timeout = "Codex took too long. Try a shorter question."
    case cancelled = "Stopped."
    case tooLarge = "This chat exceeds the compact context limit. Continue in App or start a new chat."
    case unsafe = "The provider attempted an unsupported action. Quick Chat stopped safely."
    var errorDescription: String? { rawValue }
}

enum QuickChatPolicy {
    static func allowsNotchPan(isOpen: Bool, chatSelected: Bool) -> Bool { !(isOpen && chatSelected) }
    static let maximumInputBytes = 16_384
    static let maximumContextBytes = 65_536
    static let maximumAnswerBytes = 32_768
    static let defaultInactivitySeconds: TimeInterval = 3 * 60 * 60

    static func inactivityMinutes(stored: Double?) -> Double {
        // An absent old default migrates to three hours. Any explicit stored
        // value (including 15) is preserved because intent cannot be inferred.
        guard let stored, stored.isFinite else { return defaultInactivitySeconds / 60 }
        return max(1, min(1440, stored))
    }

    static func displayMessages(_ messages: [QuickChatMessage], pendingQuestion: String?) -> [QuickChatMessage] {
        guard let pendingQuestion else { return messages }
        return messages + [.init(role: .user, text: pendingQuestion)]
    }

    static func recoveredDraft(current: String, submitted: String) -> String {
        current.isEmpty ? submitted : current
    }

    /// An idle completed response is not unfinished; a draft, active request or
    /// current reading/editing interaction is. Media is never observed to switch
    /// tabs mid-interaction. This policy is applied only on a fresh opening.
    enum Tab: Equatable { case home, shelf, chat }
    static func openingTab(automatic: Bool, existing: Tab, drag: Bool,
                           unfinished: Bool, media: Bool, shelf: Bool, ready: Bool) -> Tab {
        if drag { return .shelf }
        guard automatic else { return existing }
        if ready && unfinished { return .chat }
        if media { return .home }
        if shelf { return .shelf }
        return ready ? .chat : existing
    }

    static func shouldExpire(closedAt: Date?, now: Date, timeout: TimeInterval,
                             generating: Bool, interacting: Bool) -> Bool {
        guard !generating, !interacting, let closedAt else { return false }
        return now.timeIntervalSince(closedAt) >= max(60, timeout)
    }

    /// The transcript is transported as quoted JSON data, not additional
    /// instructions, and is sent via stdin rather than process arguments.
    static func context(messages: [QuickChatMessage], question: String,
                        citations: [QuickChatCitation]) throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.utf8.count <= maximumInputBytes else { throw QuickChatError.tooLarge }
        let value: [String: Any] = [
            "conversation": messages.map { ["role": $0.role.rawValue, "text": $0.text] },
            "request": question,
            "untrustedKnowledgeExcerpts": citations.map { [
                "citation": $0.id, "file": $0.relativePath, "excerpt": $0.excerpt,
                "modified": $0.modifiedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "Unknown"
            ] }
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= maximumContextBytes else { throw QuickChatError.tooLarge }
        return String(decoding: data, as: UTF8.self)
    }
}

struct CodexQuickChatHandoff: QuickChatHandoffDestination {
    let name = "Codex"
    func prefillURL(context: String) -> URL? {
        // Conservative client cap; oversized payloads use explicit Copy instead.
        guard !context.isEmpty, !context.contains("\0"), context.utf8.count <= 8_192 else { return nil }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/new"
        components.queryItems = [URLQueryItem(name: "prompt", value: context)]
        guard let url = components.url, url.absoluteString.utf8.count <= 24_576 else { return nil }
        return url
    }
}
