import Foundation

enum MediaDownloadFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case bestOriginal = "Best original quality"
    case mp4 = "Video (MP4)"
    case mp3 = "Audio (MP3)"

    var id: String { rawValue }
}

enum MediaDownloadJobState: String, Codable, Sendable {
    case queued, inspecting, downloading, processing, completed, cancelled, failed
}

struct MediaInspection: Sendable {
    let url: URL
    let title: String
    let sourceService: String
    let duration: Double?
    let thumbnailURL: URL?
    let isPlaylist: Bool
    let itemCount: Int?
}

struct MediaDownloadResult: Sendable {
    let inspection: MediaInspection
    let files: [URL]
}

enum MediaDownloaderError: LocalizedError {
    case unavailable
    case invalidURL
    case inspectionFailed(String)
    case playlistConfirmationRequired(Int?)
    case downloadFailed(String)
    case unsafeOutput
    case noOutput

    var errorDescription: String? {
        switch self {
        case .unavailable: "yt-dlp is not installed. Install it with Homebrew to enable downloads."
        case .invalidURL: "Enter a valid HTTP or HTTPS media URL."
        case .inspectionFailed(let message): "The media URL could not be inspected: \(message)"
        case .playlistConfirmationRequired(let count):
            count.map { "This URL contains a playlist with \($0) items. Confirm the playlist before downloading." }
                ?? "This URL contains a playlist. Confirm it before downloading."
        case .downloadFailed(let message): "The download failed: \(message)"
        case .unsafeOutput: "The downloader produced an output outside the selected download directory."
        case .noOutput: "The downloader finished without producing a media file."
        }
    }
}

actor MediaDownloaderService {
    static let shared = MediaDownloaderService()

    static let pinnedTestedVersion = "2026.7.4"
    static let candidateExecutables = [
        URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"),
        URL(fileURLWithPath: "/usr/local/bin/yt-dlp")
    ]
    static let ffmpegCandidates = [
        URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
        URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
    ]

    nonisolated static func validatedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 8_192,
              let components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            throw MediaDownloaderError.invalidURL
        }
        return url
    }

    func inspect(_ url: URL) async throws -> MediaInspection {
        let executable = try await requiredExecutable()
        let result = try await SafeProcessRunner.runApproved(
            engine: "yt-dlp",
            executable: executable,
            arguments: baseArguments + ["--dump-single-json", "--flat-playlist", url.absoluteString],
            timeout: .seconds(90),
            maximumLogBytes: 1_048_576
        )
        guard result.exitCode == 0 else {
            throw MediaDownloaderError.inspectionFailed(redactedError(result.standardError, url: url))
        }
        guard let data = result.standardOutput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloaderError.inspectionFailed("yt-dlp returned invalid metadata.")
        }

        let entries = object["entries"] as? [Any]
        return MediaInspection(
            url: url,
            title: (object["title"] as? String)?.prefix(300).description ?? url.host ?? "Media",
            sourceService: (object["extractor_key"] as? String) ?? (object["extractor"] as? String) ?? url.host ?? "Unknown",
            duration: object["duration"] as? Double,
            thumbnailURL: (object["thumbnail"] as? String).flatMap(URL.init(string:)),
            isPlaylist: entries != nil || (object["_type"] as? String) == "playlist",
            itemCount: (object["playlist_count"] as? Int) ?? entries?.count
        )
    }

    func download(
        _ inspection: MediaInspection,
        format: MediaDownloadFormat,
        destination: URL,
        playlistConfirmed: Bool,
        preserveMetadata: Bool,
        preserveThumbnail: Bool
    ) async throws -> MediaDownloadResult {
        if inspection.isPlaylist && !playlistConfirmed {
            throw MediaDownloaderError.playlistConfirmationRequired(inspection.itemCount)
        }
        let executable = try await requiredExecutable()
        let ffmpeg = await XPCHelperClient.shared.firstAvailableApprovedExecutable(
            engine: "ffmpeg",
            candidates: Self.ffmpegCandidates
        )
        let destination = destination.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MediaDownloaderError.unsafeOutput
        }

        let prefix = "Nodebay-\(UUID().uuidString)-"
        var arguments = baseArguments + [
            inspection.isPlaylist ? "--yes-playlist" : "--no-playlist",
            "--newline",
            "--no-overwrites",
            "--restrict-filenames",
            "--paths", destination.path,
            "--output", "\(prefix)%(title).180B-[%(id)s].%(ext)s"
        ]
        if let ffmpeg {
            arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        switch format {
        case .bestOriginal:
            arguments += ["--format", "bestvideo*+bestaudio/best"]
        case .mp4:
            arguments += ["--format", "bestvideo*[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best", "--merge-output-format", "mp4"]
        case .mp3:
            guard ffmpeg != nil else { throw MediaDownloaderError.unavailable }
            arguments += ["--extract-audio", "--audio-format", "mp3"]
        }
        arguments.append(preserveMetadata ? "--embed-metadata" : "--no-embed-metadata")
        arguments.append(preserveThumbnail ? "--write-thumbnail" : "--no-write-thumbnail")
        arguments.append(inspection.url.absoluteString)

        let result = try await SafeProcessRunner.runApproved(
            engine: "yt-dlp",
            executable: executable,
            arguments: arguments,
            timeout: .seconds(7_200),
            maximumLogBytes: 262_144
        )
        guard result.exitCode == 0 else {
            throw MediaDownloaderError.downloadFailed(redactedError(result.standardError, url: inspection.url))
        }

        let generated = try FileManager.default.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }

        guard !generated.isEmpty else { throw MediaDownloaderError.noOutput }
        var finalFiles: [URL] = []
        for generatedURL in generated {
            guard generatedURL.standardizedFileURL.path.hasPrefix(destination.path + "/") else {
                throw MediaDownloaderError.unsafeOutput
            }
            let cleanName = String(generatedURL.lastPathComponent.dropFirst(prefix.count))
            let finalURL = collisionSafeURL(in: destination, filename: cleanName)
            try FileManager.default.moveItem(at: generatedURL, to: finalURL)
            finalFiles.append(finalURL)
        }
        return MediaDownloadResult(inspection: inspection, files: finalFiles)
    }

    private var baseArguments: [String] {
        ["--ignore-config", "--no-config-locations", "--no-plugin-dirs", "--no-cookies-from-browser"]
    }

    private func requiredExecutable() async throws -> URL {
        guard let executable = await XPCHelperClient.shared.firstAvailableApprovedExecutable(
            engine: "yt-dlp",
            candidates: Self.candidateExecutables
        ) else { throw MediaDownloaderError.unavailable }
        return executable
    }

    private func collisionSafeURL(in directory: URL, filename: String) -> URL {
        let initial = directory.appending(path: filename)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        let stem = initial.deletingPathExtension().lastPathComponent
        let ext = initial.pathExtension
        var counter = 2
        while true {
            let candidate = directory.appending(path: "\(stem)-\(counter)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private func redactedError(_ value: String, url: URL) -> String {
        let line = value.components(separatedBy: .newlines).last(where: { !$0.isEmpty }) ?? "Unknown error"
        return String(line.replacingOccurrences(of: url.absoluteString, with: "[media URL]").prefix(500))
    }
}
