import Foundation

enum MediaDownloadSelectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic = "Automatic (Recommended)"
    case alwaysVideo = "Always Video"
    case alwaysAudio = "Always Audio"
    case askEveryTime = "Ask Every Time"

    var id: String { rawValue }

    static var stored: Self {
        stored(in: .standard)
    }

    static func stored(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: "nodebay.downloader.selectionMode")
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

/// Diagnostics use only the ordinal and fixed classifier labels, never a title,
/// artist, video ID, or URL. Optional job storage keeps older jobs decodable.
struct MediaPlaylistItemDecision: Codable, Equatable, Sendable {
    let index: Int
    let classification: MediaDownloadClassification
}

struct MediaClassificationMetadata: Codable, Equatable, Sendable {
    let url: URL
    let categories: [String]
    let track: String?
    let artist: String?
    let mediaType: String?
    let videoCodec: String?
    let audioCodec: String?
    // nil means the extractor did not provide a complete format list.
    var hasVideoFormats: Bool? = nil

    static func from(_ object: [String: Any], url: URL) -> Self {
        let formats = object["formats"] as? [[String: Any]]
        let knownFormats = formats?.filter { $0["vcodec"] as? String != nil }
        let hasVideo = knownFormats?.isEmpty == false ? knownFormats?.contains {
            let codec = ($0["vcodec"] as? String ?? "").lowercased()
            return !codec.isEmpty && codec != "none"
        } : nil
        return Self(
            url: url, categories: object["categories"] as? [String] ?? [],
            track: object["track"] as? String,
            artist: (object["artist"] as? String) ?? (object["artists"] as? [String])?.first,
            mediaType: object["media_type"] as? String,
            // An incomplete list cannot prove that the entire upload is audio-only.
            videoCodec: formats != nil && knownFormats?.count != formats?.count ? nil : object["vcodec"] as? String,
            audioCodec: object["acodec"] as? String,
            hasVideoFormats: hasVideo
        )
    }
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
        if metadata.hasVideoFormats != true && (mediaType == "audio" ||
            (videoCodec == "none" && audioCodec?.isEmpty == false && audioCodec != "none")) {
            return .init(kind: .audio, confidence: .high, reason: "Extractor reports audio-only media")
        }

        let hasTrack = metadata.track?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasArtist = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if hasTrack && hasArtist {
            return .init(kind: .audio, confidence: .high, reason: "Extractor provides structured track and artist metadata")
        }

        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return .init(kind: .video, confidence: .safeFallback, reason: "Ambiguous YouTube media defaults to video to preserve content")
        }
        return .init(kind: .video, confidence: .safeFallback, reason: "No reliable audio-only metadata; preserving video")
    }
}
