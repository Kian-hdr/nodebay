//
//  BundleInfos.swift
//  boringNotch
//
//  Created by Richard Kunkli on 08/08/2024.
//

import SwiftUI

enum NodebayBrand {
    static let name = "Nodebay"
    static let tagline = "The utility bay in your Mac’s notch."
    static let creator = "Kian Konrad Tajbakhsh"
    static let copyright = "Copyright © 2026 Kian Konrad Tajbakhsh."
    static let sourceURL = URL(string: "https://github.com/Kian-hdr/nodebay")!
    static let releasesURL = sourceURL.appending(path: "releases")
    static let issuesURL = sourceURL.appending(path: "issues")
    static let licenseURL = sourceURL.appending(path: "blob/main/LICENSE")
    static let acknowledgementsURL = sourceURL.appending(path: "blob/main/ACKNOWLEDGEMENTS.md")
    static let thirdPartyNoticesURL = sourceURL.appending(path: "blob/main/THIRD_PARTY_NOTICES.md")
    static let privacyURL = sourceURL.appending(path: "blob/main/PRIVACY.md")
    static let securityURL = sourceURL.appending(path: "blob/main/SECURITY.md")
    static let upstreamURL = URL(string: "https://github.com/TheBoredTeam/boring.notch")!
    static let foundationCommit = "44dd999f70493da48209c99e9f873c47f2e55c83"
    static let foundationLabel = "Boring Notch dev @ 44dd999"

    // Nodebay 0.x deliberately keeps the legacy bundle identifier so existing
    // sandbox bookmarks, preferences, Accessibility permission, and saved shelf
    // state remain available. A future identifier migration requires a signed,
    // user-visible export/import handoff and must not happen silently.
    static let legacyBundleIdentifier = "theboringteam.boringnotch"
}

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
    var releaseVersionNumberPretty: String {
        return "v\(releaseVersionNumber ?? "1.0.0")"
    }
    
    var iconFileName: String? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last
        else { return nil }
        return iconFileName
    }
}

struct BundleAppIcon: View {
    var body: some View {
        Bundle.main.iconFileName
            .flatMap { NSImage(named: $0) }
            .map { Image(nsImage: $0) }
    }
}

func isNewVersion() -> Bool {
    let defaults = UserDefaults.standard
    let currentVersion = Bundle.main.releaseVersionNumber ?? "1.0"
    let savedVersion = defaults.string(forKey: "LastVersionRun") ?? ""
    
    if currentVersion != savedVersion {
        defaults.set(currentVersion, forKey: "LastVersionRun")
        return true
    }
    return false
}

func isExtensionRunning(_ bundleID: String) -> Bool {
    if let _ = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == bundleID}) {
        return true
    }
    
    return false
}
