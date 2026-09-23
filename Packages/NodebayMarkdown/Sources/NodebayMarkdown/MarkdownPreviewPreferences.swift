// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Shared by the app and its independently hosted Quick Look extension.
public enum MarkdownPreviewPreferences {
    public static let defaultSolidBackground = true
    public static let solidBackgroundKey = "markdownPreviewSolidBackground"
    public static let defaults: UserDefaults = {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "NodebayPreviewAppGroup") as? String,
              !group.isEmpty, let defaults = UserDefaults(suiteName: group) else {
            preconditionFailure("Missing Nodebay preview App Group configuration")
        }
        return defaults
    }()
}
