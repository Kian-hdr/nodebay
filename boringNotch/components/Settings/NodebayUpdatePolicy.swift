import Foundation

/// Sparkle owns its preferences. This marker records only whether Nodebay has
/// offered the first real updater choice; legacy forced-false values are ambiguous.
enum NodebayUpdatePreferences {
    static let choiceKey = "nodebay.updates.explicitChoiceVersion"
    static let choiceVersion = 1

    static func needsChoice(in defaults: UserDefaults) -> Bool {
        defaults.integer(forKey: choiceKey) < choiceVersion
    }

    static func recordChoice(in defaults: UserDefaults) {
        defaults.set(choiceVersion, forKey: choiceKey)
    }
}

struct NodebayUpdateConfiguration {
    static let stableFeed = "https://raw.githubusercontent.com/Kian-hdr/nodebay/updates/stable/appcast.xml"
    static let testingFeed = "https://raw.githubusercontent.com/Kian-hdr/nodebay/updates/testing/appcast.xml"
    let feedURL: URL

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              [Self.stableFeed, Self.testingFeed].contains(feed),
              let url = URL(string: feed),
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SUSignedFeedFailureExpirationInterval"] as? Int == 0 else { return nil }
        feedURL = url
    }
}

enum NodebayUpdateCheckPolicy {
    static func validate(isUserInitiated: Bool, isConfigured: Bool, needsChoice: Bool) throws {
        guard isConfigured else {
            throw NSError(domain: "NodebayUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "The signed Nodebay updater is not configured."])
        }
        guard isUserInitiated || !needsChoice else {
            throw NSError(domain: "NodebayUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose your automatic update preference in About Nodebay."])
        }
    }
}

/// Retains Sparkle's one-shot continuation until current work is actually idle.
/// The final application-termination gate rechecks for jobs started afterward.
@MainActor
final class NodebayUpdateInstallGate {
    private let isBusy: () -> Bool
    private let flush: () -> Void
    private var continuation: (() -> Void)?
    var isWaiting: Bool { continuation != nil }

    init(isBusy: @escaping () -> Bool, flush: @escaping () -> Void) {
        self.isBusy = isBusy
        self.flush = flush
    }

    func postpone(_ install: @escaping () -> Void) -> Bool {
        guard isBusy() else { flush(); return false }
        continuation = install
        return true
    }

    func resumeIfIdle() {
        guard !isBusy(), let install = continuation else { return }
        continuation = nil
        flush()
        install()
    }

    func cancel() { continuation = nil }

    func canTerminate() -> Bool {
        guard !isBusy() else { return false }
        flush()
        return true
    }
}
