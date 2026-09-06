//
//  PlaybackState.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

enum RepeatMode: Int, Codable {
    case off = 1
    case one = 2
    case all = 3
}

struct PlaybackState {
    var bundleIdentifier: String
    var audioCaptureBundleIdentifiers: [String] = []
    var isPlaying: Bool = false
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Double = 1
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var lastUpdated: Date = Date.distantPast
    var artwork: Data?
    var volume: Double = 0.5
    var isFavorite: Bool = false

    /// A running application alone is not a playable media session. Paused
    /// tracks still have metadata and must remain independently selectable.
    var hasMedia: Bool {
        isPlaying || duration > 0 || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func representsSameItem(as other: PlaybackState) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !bundleIdentifier.isEmpty && bundleIdentifier == other.bundleIdentifier
            && !name.isEmpty
            && name.caseInsensitiveCompare(other.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    var effectiveAudioCaptureBundleIdentifiers: [String] {
        let raw = audioCaptureBundleIdentifiers.isEmpty ? [bundleIdentifier] : audioCaptureBundleIdentifiers
        return raw.normalizedBundleIdentifiers
    }
}

extension Sequence where Element == String {
    var normalizedBundleIdentifiers: [String] {
        var seen = Set<String>()
        return filter { value in
            guard !value.isEmpty, !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }
}

extension PlaybackState: Equatable {
    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.effectiveAudioCaptureBundleIdentifiers == rhs.effectiveAudioCaptureBundleIdentifiers
            && lhs.isPlaying == rhs.isPlaying
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.currentTime == rhs.currentTime
            && lhs.duration == rhs.duration
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artwork == rhs.artwork
            && lhs.isFavorite == rhs.isFavorite
    }
}

/// Shared source-list and fallback policy, independent of app discovery and UI.
struct MediaSessionCandidate<ID: Hashable> {
    let id: ID
    let state: PlaybackState
    let isAvailable: Bool
    let isGeneric: Bool
    let isAppSource: Bool
}

enum MediaSessionSelection {
    static func visible<ID>(_ candidates: [MediaSessionCandidate<ID>]) -> [MediaSessionCandidate<ID>] {
        let available = candidates.filter { $0.isAvailable && $0.state.hasMedia }
        return available.filter { candidate in
            guard candidate.isGeneric else { return true }
            // A unique known target can replace the generic feed. Never guess
            // between two browser tabs with the same title.
            return available.filter {
                !$0.isGeneric && candidate.state.bundleIdentifier == $0.state.bundleIdentifier
                    && ($0.isAppSource || candidate.state.representsSameItem(as: $0.state))
            }.count != 1
        }
    }

    static func selectedID<ID>(current: ID, preferred: ID, candidates: [MediaSessionCandidate<ID>]) -> ID? {
        let choices = visible(candidates)
        if choices.contains(where: { $0.id == current }) { return current }
        if let old = candidates.first(where: { $0.id == current && $0.isAvailable }) {
            let equivalents = choices.filter {
                old.state.representsSameItem(as: $0.state)
                    || (old.isGeneric && $0.isAppSource && !old.state.bundleIdentifier.isEmpty
                        && old.state.bundleIdentifier == $0.state.bundleIdentifier)
            }
            if equivalents.count == 1 { return equivalents[0].id }
        }
        return choices.first(where: { $0.id == preferred })?.id
            ?? choices.first(where: { $0.state.isPlaying })?.id
            ?? choices.first?.id
    }
}
