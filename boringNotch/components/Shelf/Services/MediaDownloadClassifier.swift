import Foundation

enum MediaDownloadSelectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "Automatic (Recommended)"
    case alwaysVideo = "Always Video"
    case alwaysAudio = "Always Audio"
    case askEveryTime = "Ask Every Time"

    var id: String { rawValue }

    static var stored: Self {
        UserDefaults.standard.string(forKey: "nodebay.downloader.selectionMode")
            .flatMap(Self.init(rawValue:)) ?? .automatic
    }
}

enum MediaDownloadKind: String, Codable, Sendable {
    case audio
    case video
}

enum MediaClassificationConfidence: String, Codable, Sendable {
    case high
    case medium
    case safeFallback
}

struct MediaDownloadClassification: Codable, Equatable, Sendable {
    let kind: MediaDownloadKind
    let confidence: MediaClassificationConfidence
    let reason: String
}

struct MediaClassificationMetadata: Codable, Equatable, Sendable {
    let url: URL
    let categories: [String]
    let track: String?
    let artist: String?
    let mediaType: String?
    let videoCodec: String?
    let audioCodec: String?
}

enum MediaDownloadClassifier {
    static func classify(_ metadata: MediaClassificationMetadata) -> MediaDownloadClassification {
        let host = metadata.url.host?.lowercased() ?? ""
        if host == "music.youtube.com" || host.hasSuffix(".music.youtube.com") {
            return .init(kind: .audio, confidence: .high, reason: "YouTube Music source URL")
        }

        let mediaType = metadata.mediaType?.lowercased()
        let videoCodec = metadata.videoCodec?.lowercased()
        let audioCodec = metadata.audioCodec?.lowercased()
        if mediaType == "audio" || (videoCodec == "none" && audioCodec != nil && audioCodec != "none") {
            return .init(kind: .audio, confidence: .high, reason: "Extractor reports audio-only media")
        }

        let hasTrack = metadata.track?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasArtist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let musicCategory = metadata.categories.contains {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .localizedCaseInsensitiveContains("music")
        }
        if hasTrack && hasArtist {
            return .init(kind: .audio, confidence: .high, reason: "Extractor provides structured track and artist metadata")
        }
        if musicCategory && (hasTrack || hasArtist) {
            return .init(kind: .audio, confidence: .medium, reason: "Music category with structured track or artist metadata")
        }

        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return .init(kind: .video, confidence: .safeFallback, reason: "Ambiguous YouTube media defaults to video to preserve content")
        }
        return .init(kind: .video, confidence: .safeFallback, reason: "No reliable audio-only metadata; preserving video")
    }
}
