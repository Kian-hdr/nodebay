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
    static let creator = "Kian"
    static let copyright = "Copyright © 2026 Kian."
    static let sourceURL = URL(string: "https://github.com/Kian-hdr/nodebay")!
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
