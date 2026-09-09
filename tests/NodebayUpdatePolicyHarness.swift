import Foundation

@main
struct NodebayUpdatePolicyHarness {
    @MainActor
    static func main() throws {
        switch CommandLine.arguments[1] {
        case "migration":
            try migration()
        case "configuration":
            configuration()
        case "check-requests":
            checkRequests()
        case "defer-install":
            deferInstall()
        case "termination-race":
            terminationRace()
        case "cancel-install":
            cancelInstall()
        default:
            fatalError("Unknown test case")
        }
        print("Updater policy checks passed")
    }

    static func migration() throws {
        let suite = "NodebayUpdaterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let checkKey = "SUEnableAutomaticChecks"
        let downloadKey = "SUAutomaticallyUpdate"
        // Neither missing values nor historical true/false values prove a choice.
        for legacyValue: Bool? in [nil, false, true] {
            defaults.removePersistentDomain(forName: suite)
            if let legacyValue {
                defaults.set(legacyValue, forKey: checkKey)
                defaults.set(legacyValue, forKey: downloadKey)
            }
            let before = defaults.persistentDomain(forName: suite) ?? [:]
            precondition(NodebayUpdatePreferences.needsChoice(in: defaults))
            let after = defaults.persistentDomain(forName: suite) ?? [:]
            precondition(NSDictionary(dictionary: before).isEqual(to: after), "Migration detection must not change preferences")
        }
        // Explicit opt-out survives a future launch; recording it never rewrites
        // Sparkle's actual preferences or infers a different download preference.
        defaults.set(false, forKey: checkKey)
        defaults.set(true, forKey: downloadKey)
        NodebayUpdatePreferences.recordChoice(in: defaults)
        let nextLaunch = UserDefaults(suiteName: suite)!
        precondition(!NodebayUpdatePreferences.needsChoice(in: nextLaunch))
        precondition(!nextLaunch.bool(forKey: checkKey))
        precondition(nextLaunch.bool(forKey: downloadKey))
        defaults.set(0, forKey: NodebayUpdatePreferences.choiceKey)
        precondition(NodebayUpdatePreferences.needsChoice(in: defaults))
        defaults.set(2, forKey: NodebayUpdatePreferences.choiceKey)
        precondition(!NodebayUpdatePreferences.needsChoice(in: defaults))
    }

    static func configuration() {
        let valid: [String: Any] = [
            "SUFeedURL": NodebayUpdateConfiguration.stableFeed,
            "SUPublicEDKey": "p5wX3wvGOSYWwjHEHmQ09cb4J7TwCTmcf5V+4iNhoDA=",
            "SURequireSignedFeed": true,
            "SUVerifyUpdateBeforeExtraction": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]
        precondition(NodebayUpdateConfiguration(info: valid)?.feedURL.absoluteString == NodebayUpdateConfiguration.stableFeed)
        var testing = valid
        testing["SUFeedURL"] = NodebayUpdateConfiguration.testingFeed
        precondition(NodebayUpdateConfiguration(info: testing) != nil)
        for field in valid.keys {
            var missing = valid
            missing.removeValue(forKey: field)
            precondition(NodebayUpdateConfiguration(info: missing) == nil, "Missing \(field) must fail closed")
        }
        let invalid: [(String, Any)] = [
            ("SUFeedURL", "$(NODEBAY_UPDATE_FEED_URL)"),
            ("SUFeedURL", "http://raw.githubusercontent.com/Kian-hdr/nodebay/updates/stable/appcast.xml"),
            ("SUFeedURL", "https://example.com/upstream/appcast.xml"),
            ("SUFeedURL", NodebayUpdateConfiguration.stableFeed + "?redirect=1"),
            ("SUPublicEDKey", "$(NODEBAY_UPDATE_PUBLIC_ED_KEY)"),
            ("SUPublicEDKey", Data(repeating: 1, count: 31).base64EncodedString()),
            ("SURequireSignedFeed", false),
            ("SUVerifyUpdateBeforeExtraction", false),
            ("SUSignedFeedFailureExpirationInterval", 20 * 86400)
        ]
        for (field, value) in invalid {
            var info = valid
            info[field] = value
            precondition(NodebayUpdateConfiguration(info: info) == nil, "Invalid \(field) must fail closed")
        }
    }

    static func checkRequests() {
        for configured in [false, true] {
            for needsChoice in [false, true] {
                for manual in [false, true] {
                    do {
                        try NodebayUpdateCheckPolicy.validate(isUserInitiated: manual, isConfigured: configured, needsChoice: needsChoice)
                        precondition(configured && (manual || !needsChoice))
                    } catch {
                        let error = error as NSError
                        precondition(error.domain == "NodebayUpdater")
                        precondition(error.code == (!configured ? 1 : 2))
                        precondition(!configured || (!manual && needsChoice))
                    }
                }
            }
        }
    }

    @MainActor
    static func deferInstall() {
        var busy = true
        var events = [String]()
        let gate = NodebayUpdateInstallGate(isBusy: { busy }, flush: { events.append("persist") })
        precondition(gate.postpone { events.append("install") })
        precondition(gate.isWaiting)
        for _ in 0..<3 { gate.resumeIfIdle() }
        precondition(events.isEmpty)
        busy = false
        gate.resumeIfIdle()
        precondition(events == ["persist", "install"])
        precondition(!gate.isWaiting)
        gate.resumeIfIdle()
        precondition(events == ["persist", "install"], "Continuation must run once")
        precondition(!gate.postpone { fatalError("Idle path must let Sparkle continue itself") })
        precondition(events == ["persist", "install", "persist"])
    }

    @MainActor
    static func terminationRace() {
        var busy = true
        var flushCount = 0
        let gate = NodebayUpdateInstallGate(isBusy: { busy }, flush: { flushCount += 1 })
        precondition(gate.postpone { busy = true })
        busy = false
        gate.resumeIfIdle() // A new job starts before Sparkle asks the app to quit.
        precondition(!gate.canTerminate())
        precondition(flushCount == 1)
        busy = false
        precondition(gate.canTerminate())
        precondition(flushCount == 2)
        busy = true
        // Also covers resumed installs for which Sparkle does not call postpone.
        precondition(!gate.canTerminate())
        precondition(flushCount == 2)
    }

    @MainActor
    static func cancelInstall() {
        var busy = true
        var events = [String]()
        let gate = NodebayUpdateInstallGate(isBusy: { busy }, flush: { events.append("persist") })
        precondition(gate.postpone { events.append("cancelled install") })
        gate.cancel()
        precondition(!gate.isWaiting)
        busy = false
        gate.resumeIfIdle()
        precondition(events.isEmpty)
        busy = true
        precondition(gate.postpone { events.append("retry") })
        busy = false
        gate.resumeIfIdle()
        precondition(events == ["persist", "retry"])
    }
}
