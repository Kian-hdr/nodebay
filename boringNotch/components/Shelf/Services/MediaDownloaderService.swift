import AppKit
import Foundation

enum MediaDownloadFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case bestOriginal = "Best original quality"
    case mp4 = "Video (MP4)"
    case mp3 = "Audio (MP3)"
    var id: String { rawValue }
}

enum MediaDownloadJobState: String, Codable, Sendable {
    case queued, inspecting, awaitingFormat, downloading, processing, completed, cancelled, failed
}

struct MediaDownloadOptions: Codable, Equatable, Sendable {
    var format: MediaDownloadFormat
    var maximumVideoHeight: Int?
    var audioBitrate: Int?

    static var storedDefault: Self {
        let defaults = UserDefaults.standard
        return Self(
            format: defaults.string(forKey: "nodebay.downloader.defaultFormat").flatMap(MediaDownloadFormat.init(rawValue:)) ?? .bestOriginal,
            maximumVideoHeight: integer(from: defaults.string(forKey: "nodebay.downloader.preferredResolution")),
            audioBitrate: integer(from: defaults.string(forKey: "nodebay.downloader.audioBitrate"))
        )
    }

    func saveAsDefault() {
        let defaults = UserDefaults.standard
        defaults.set(format.rawValue, forKey: "nodebay.downloader.defaultFormat")
        defaults.set(maximumVideoHeight.map { "\($0)p" } ?? "Best available", forKey: "nodebay.downloader.preferredResolution")
        defaults.set(audioBitrate.map { "\($0) kbps" } ?? "Best available", forKey: "nodebay.downloader.audioBitrate")
        defaults.set(false, forKey: "nodebay.downloader.askEveryTime")
    }

    private static func integer(from value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.prefix { $0.isNumber })
    }
}

struct MediaInspection: Codable, Sendable {
    let url: URL
    let title: String
    let sourceService: String
    let duration: Double?
    let thumbnailURL: URL?
    let isPlaylist: Bool
    let itemCount: Int?

    var isYouTube: Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}

struct MediaDownloadResult: Sendable {
    let inspection: MediaInspection
    let files: [URL]
    let partialFailure: String?
}

struct MediaDownloadProgress: Sendable {
    let stage: MediaDownloadJobState
    let percentage: Double?
    let downloadedBytes: Int64?
    let totalBytes: Int64?
    let speed: Double?
    let eta: Double?
}

struct MediaDownloadJob: Identifiable, Codable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var sourceService: String
    var state: MediaDownloadJobState
    var isPlaylist: Bool
    var itemCount: Int?
    var options: MediaDownloadOptions?
    var progress: Double?
    var lastError: String?
    var completedPaths: [String]
}

enum MediaDownloaderError: LocalizedError {
    case unavailable, ffmpegUnavailable, invalidURL
    case inspectionFailed(String), playlistConfirmationRequired(Int?), downloadFailed(String)
    case youtubeRequestRejected, youtubeSearchFailed
    case unsafeOutput, noOutput

    var errorDescription: String? {
        switch self {
        case .unavailable: "yt-dlp is not installed. Install it with Homebrew to enable downloads."
        case .ffmpegUnavailable: "FFmpeg is required for this format. Install it with Homebrew and try again."
        case .invalidURL: "Enter a valid HTTP or HTTPS media URL."
        case .inspectionFailed(let message): "The media URL could not be inspected: \(message)"
        case .playlistConfirmationRequired(let count): count.map { "This playlist contains \($0) items. Confirm it before downloading." } ?? "Confirm the playlist before downloading."
        case .downloadFailed(let message): "The download failed: \(message)"
        case .youtubeRequestRejected: "YouTube rejected the media request (HTTP 403). Update yt-dlp with `brew upgrade yt-dlp`, then retry. Nodebay does not access browser cookies automatically."
        case .youtubeSearchFailed: "Nodebay could not safely identify the current YouTube item from its title and artist. Select the exact browser tab from the media-source menu, then try again."
        case .unsafeOutput: "The downloader produced an output outside the selected download directory."
        case .noOutput: "The downloader finished without producing a media file."
        }
    }
}

actor MediaDownloaderService {
    static let shared = MediaDownloaderService()
    static let pinnedTestedVersion = "2026.8.19"
    static let candidateExecutables = [URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), URL(fileURLWithPath: "/usr/local/bin/yt-dlp")]
    static let ffmpegCandidates = [URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), URL(fileURLWithPath: "/usr/local/bin/ffmpeg")]

    nonisolated static func validatedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 8_192,
              let components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host?.isEmpty == false, components.user == nil, components.password == nil,
              let url = components.url else { throw MediaDownloaderError.invalidURL }
        return url
    }

    nonisolated static func validatedURLs(in text: String) -> [URL] {
        guard text.utf8.count <= 65_536 else { return [] }
        var candidates: [String] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            candidates = detector.matches(in: text, range: range).compactMap(\.url?.absoluteString)
        }
        if candidates.isEmpty { candidates = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty } }
        var seen = Set<String>()
        return candidates.compactMap { try? validatedURL(from: $0) }.filter { seen.insert($0.absoluteString).inserted }
    }

    func isFFmpegAvailable() async -> Bool {
        await XPCHelperClient.shared.firstAvailableApprovedExecutable(engine: "ffmpeg", candidates: Self.ffmpegCandidates) != nil
    }

    func inspect(_ url: URL) async throws -> MediaInspection {
        let executable = try await requiredExecutable()
        let result = try await SafeProcessRunner.runApproved(
            engine: "yt-dlp", executable: executable,
            arguments: baseArguments + ["--dump-single-json", "--flat-playlist", url.absoluteString],
            timeout: .seconds(90), maximumLogBytes: 1_048_576
        )
        guard result.exitCode == 0 else { throw MediaDownloaderError.inspectionFailed(redactedError(result.standardError, url: url)) }
        guard let data = result.standardOutput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloaderError.inspectionFailed("yt-dlp returned invalid metadata.")
        }
        let entries = object["entries"] as? [Any]
        return MediaInspection(
            url: url, title: (object["title"] as? String)?.prefix(300).description ?? url.host ?? "Media",
            sourceService: (object["extractor_key"] as? String) ?? (object["extractor"] as? String) ?? url.host ?? "Unknown",
            duration: object["duration"] as? Double,
            thumbnailURL: (object["thumbnail"] as? String).flatMap(URL.init(string:)),
            isPlaylist: entries != nil || (object["_type"] as? String) == "playlist",
            itemCount: (object["playlist_count"] as? Int) ?? entries?.count
        )
    }

    /// Resolves System Now Playing metadata through yt-dlp when Chrome exposes
    /// only a generic YouTube Music page. The result must closely match both
    /// the title and artist so Nodebay never silently downloads a random hit.
    func resolveYouTubeSearchURL(title: String, artist: String) async throws -> URL {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        let artist = String(artist.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        let titleTokens = Self.searchTokens(title)
        guard !titleTokens.isEmpty else { throw MediaDownloaderError.youtubeSearchFailed }

        let executable = try await requiredExecutable()
        let query = [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
        let result = try await SafeProcessRunner.runApproved(
            engine: "yt-dlp", executable: executable,
            arguments: baseArguments + ["--dump-single-json", "--flat-playlist", "ytsearch5:\(query)"],
            timeout: .seconds(90), maximumLogBytes: 262_144
        )
        guard result.exitCode == 0,
              let data = result.standardOutput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["entries"] as? [[String: Any]] else {
            throw MediaDownloaderError.youtubeSearchFailed
        }

        let artistTokens = Self.searchTokens(artist).subtracting(Self.searchStopWords)
        let matches = entries.compactMap { entry -> (url: URL, score: Int)? in
            guard let rawURL = entry["url"] as? String,
                  let url = try? Self.validatedURL(from: rawURL) else { return nil }
            let candidateText = [entry["title"] as? String, entry["uploader"] as? String]
                .compactMap { $0 }
                .joined(separator: " ")
            let candidateTokens = Self.searchTokens(candidateText)
            guard titleTokens.isSubset(of: candidateTokens),
                  artistTokens.isEmpty || !artistTokens.isDisjoint(with: candidateTokens) else { return nil }
            let score = titleTokens.intersection(candidateTokens).count * 4
                + artistTokens.intersection(candidateTokens).count * 2
            return (url, score)
        }
        guard let best = matches.max(by: { $0.score < $1.score }) else {
            throw MediaDownloaderError.youtubeSearchFailed
        }
        return best.url
    }

    func download(
        _ inspection: MediaInspection, options: MediaDownloadOptions, destination: URL,
        playlistConfirmed: Bool, preserveMetadata: Bool, preserveThumbnail: Bool,
        progress: (@Sendable (MediaDownloadProgress) -> Void)? = nil
    ) async throws -> MediaDownloadResult {
        if inspection.isPlaylist && !playlistConfirmed { throw MediaDownloaderError.playlistConfirmationRequired(inspection.itemCount) }
        let executable = try await requiredExecutable()
        let ffmpeg = await XPCHelperClient.shared.firstAvailableApprovedExecutable(engine: "ffmpeg", candidates: Self.ffmpegCandidates)
        let requestedDestination = destination.standardizedFileURL
        try FileManager.default.createDirectory(at: requestedDestination, withIntermediateDirectories: true)
        // Sandboxed Downloads URLs are commonly exposed through
        // ~/Library/Containers/<bundle>/Data/Downloads, which is a symlink to
        // ~/Downloads. yt-dlp and FileManager can therefore report two
        // different lexical paths for the same directory. Canonicalize only
        // after the selected directory exists so containment checks compare
        // filesystem identity instead of path spelling.
        let destination = requestedDestination.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw MediaDownloaderError.unsafeOutput }
        if options.format == .mp3 && ffmpeg == nil { throw MediaDownloaderError.ffmpegUnavailable }

        let staging = destination.appending(path: ".nodebay-download-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        var arguments = baseArguments + [
            inspection.isPlaylist ? "--yes-playlist" : "--no-playlist", "--newline", "--no-overwrites", "--restrict-filenames",
            "--paths", staging.path, "--output", "%(title).180B-[%(id)s].%(ext)s",
            "--progress-template", "download:nodebay-progress:%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"
        ]
        if let ffmpeg { arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path] }
        arguments += Self.formatArguments(options: options, ffmpegAvailable: ffmpeg != nil)
        arguments.append(preserveMetadata ? "--embed-metadata" : "--no-embed-metadata")
        arguments.append(preserveThumbnail && ffmpeg != nil ? "--embed-thumbnail" : "--no-write-thumbnail")
        arguments.append(inspection.url.absoluteString)

        let result = try await SafeProcessRunner.runApproved(
            engine: "yt-dlp", executable: executable, arguments: arguments,
            timeout: .seconds(7_200), maximumLogBytes: 262_144, progress: progress
        )
        let canonicalStaging = staging.resolvingSymlinksInPath().standardizedFileURL
        let generated = try FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
            .filter { !["part", "ytdl", "temp"].contains($0.pathExtension.lowercased()) }
        var finalFiles: [URL] = []
        for generatedURL in generated {
            // FileManager produced this entry by enumerating the app-owned
            // staging directory. Rebuild the URL from that canonical directory
            // and the single path component instead of trusting the spelling
            // returned through the sandbox's Downloads symlink.
            let filename = generatedURL.lastPathComponent
            guard !filename.isEmpty, filename != ".", filename != "..",
                  !filename.contains("/") else { throw MediaDownloaderError.unsafeOutput }
            let canonicalGenerated = canonicalStaging.appending(path: filename).standardizedFileURL
            let values = try canonicalGenerated.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard canonicalGenerated.deletingLastPathComponent().path == canonicalStaging.path,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { throw MediaDownloaderError.unsafeOutput }
            let finalURL = collisionSafeURL(in: destination, filename: canonicalGenerated.lastPathComponent)
            try FileManager.default.moveItem(at: canonicalGenerated, to: finalURL)
            finalFiles.append(finalURL)
        }
        guard !finalFiles.isEmpty else {
            if result.exitCode != 0 {
                let message = redactedError(result.standardError, url: inspection.url)
                if inspection.isYouTube && message.localizedCaseInsensitiveContains("HTTP Error 403") {
                    throw MediaDownloaderError.youtubeRequestRejected
                }
                throw MediaDownloaderError.downloadFailed(message)
            }
            throw MediaDownloaderError.noOutput
        }
        return MediaDownloadResult(
            inspection: inspection, files: finalFiles,
            partialFailure: result.exitCode == 0 ? nil : redactedError(result.standardError, url: inspection.url)
        )
    }

    nonisolated static func formatArguments(options: MediaDownloadOptions, ffmpegAvailable: Bool) -> [String] {
        let height = options.maximumVideoHeight.map { "[height<=\($0)]" } ?? ""
        switch options.format {
        case .bestOriginal:
            return ffmpegAvailable
                ? ["--format", "bestvideo*\(height)+bestaudio/best\(height)"]
                : ["--format", "best\(height)"]
        case .mp4:
            return ffmpegAvailable
                ? ["--format", "bestvideo*[ext=mp4]\(height)+bestaudio[ext=m4a]/best[ext=mp4]\(height)/best\(height)", "--merge-output-format", "mp4"]
                : ["--format", "best[ext=mp4]\(height)"]
        case .mp3:
            var result = ["--extract-audio", "--audio-format", "mp3"]
            if let bitrate = options.audioBitrate { result += ["--audio-quality", "\(bitrate)K"] }
            return result
        }
    }

    private var baseArguments: [String] { ["--ignore-config", "--no-config-locations", "--no-plugin-dirs", "--no-cookies-from-browser"] }
    private nonisolated static let searchStopWords: Set<String> = ["and", "und", "feat", "featuring", "ft", "the"]
    private nonisolated static func searchTokens(_ value: String) -> Set<String> {
        Set(value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }
    private func requiredExecutable() async throws -> URL {
        guard let executable = await XPCHelperClient.shared.firstAvailableApprovedExecutable(engine: "yt-dlp", candidates: Self.candidateExecutables) else { throw MediaDownloaderError.unavailable }
        return executable
    }
    private func collisionSafeURL(in directory: URL, filename: String) -> URL {
        let initial = directory.appending(path: filename)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        let stem = initial.deletingPathExtension().lastPathComponent, ext = initial.pathExtension
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

private actor MediaDownloadLimiter {
    static let shared = MediaDownloadLimiter()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire(limit: Int) async {
        if active < max(1, limit) { active += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { active = max(0, active - 1) } else { waiters.removeFirst().resume() }
    }
}

@MainActor final class DownloadCoordinator: ObservableObject {
    static let shared = DownloadCoordinator()
    @Published private(set) var jobs: [UUID: MediaDownloadJob] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let persistenceKey = "nodebay.downloader.jobs.v1"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let saved = try? JSONDecoder().decode([MediaDownloadJob].self, from: data) else { return }
        for var job in saved {
            if [.queued, .inspecting, .awaitingFormat, .downloading, .processing].contains(job.state) {
                job.state = .failed
                job.lastError = "The previous download was interrupted. Select Retry to continue."
            }
            jobs[job.id] = job
        }
    }

    func add(rawText: String) { add(urls: MediaDownloaderService.validatedURLs(in: rawText)) }
    func add(urls: [URL]) {
        let shelfURLs = Set(ShelfStateViewModel.shared.items.compactMap { item -> String? in
            guard case .link(let url) = item.kind else { return nil }
            return url.absoluteString
        })
        let activeURLs = Set(jobs.values.compactMap { job -> String? in
            guard [.queued, .inspecting, .awaitingFormat, .downloading, .processing].contains(job.state) else { return nil }
            return job.url.absoluteString
        })
        var seen = shelfURLs.union(activeURLs)
        let uniqueURLs = urls.filter { seen.insert($0.absoluteString).inserted }
        guard !uniqueURLs.isEmpty else { return }
        let items = uniqueURLs.map { ShelfItem(kind: .link(url: $0)) }
        ShelfStateViewModel.shared.add(items)
        start(items: items)
    }
    func start(items: [ShelfItem]) {
        for item in items where jobs[item.id] == nil {
            guard case .link(let url) = item.kind else { continue }
            jobs[item.id] = MediaDownloadJob(id: item.id, url: url, title: url.host ?? "Media", sourceService: url.host ?? "Unknown", state: .queued, isPlaylist: false, itemCount: nil, options: nil, progress: nil, lastError: nil, completedPaths: [])
            persist()
            tasks[item.id] = Task { [weak self] in await self?.run(item: item) }
        }
    }
    func retry(_ item: ShelfItem) { tasks[item.id]?.cancel(); jobs[item.id] = nil; start(items: [item]) }
    func cancel(_ item: ShelfItem) {
        tasks[item.id]?.cancel(); update(item.id) { $0.state = .cancelled; $0.lastError = nil }
        ShelfStateViewModel.shared.finishConverting([item])
    }

    private func run(item: ShelfItem) async {
        guard case .link(let sourceURL) = item.kind else { return }
        let shelf = ShelfStateViewModel.shared
        shelf.beginConverting([item]); shelf.setConversionProgress("Inspecting…", for: item)
        update(item.id) { $0.state = .inspecting }
        do {
            let inspection = try await MediaDownloaderService.shared.inspect(MediaDownloaderService.validatedURL(from: sourceURL.absoluteString))
            try Task.checkCancellation()
            update(item.id) { $0.title = inspection.title; $0.sourceService = inspection.sourceService; $0.isPlaylist = inspection.isPlaylist; $0.itemCount = inspection.itemCount; $0.state = .awaitingFormat }
            shelf.setConversionProgress("Choose Format", for: item)
            guard let options = await chooseOptions(for: inspection) else { update(item.id) { $0.state = .cancelled }; shelf.finishConverting([item]); return }
            update(item.id) { $0.options = options; $0.state = .downloading }
            shelf.setConversionProgress("Downloading…", for: item)
            let limit = UserDefaults.standard.object(forKey: "nodebay.downloader.maximumConcurrent") as? Int ?? 2
            await MediaDownloadLimiter.shared.acquire(limit: limit)
            defer { Task { await MediaDownloadLimiter.shared.release() } }
            try Task.checkCancellation()
            let destination = configuredDownloadDirectory()
            let accessed = destination.startAccessingSecurityScopedResource()
            defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
            let result = try await MediaDownloaderService.shared.download(
                inspection, options: options, destination: destination, playlistConfirmed: true,
                preserveMetadata: UserDefaults.standard.object(forKey: "nodebay.downloader.preserveMetadata") as? Bool ?? true,
                preserveThumbnail: UserDefaults.standard.bool(forKey: "nodebay.downloader.preserveThumbnail")
            ) { progress in Task { @MainActor [weak self] in self?.receive(progress, for: item) } }
            try Task.checkCancellation()
            update(item.id) { $0.state = .processing; $0.completedPaths = result.files.map(\.path); $0.lastError = result.partialFailure }
            shelf.setConversionProgress("Adding to Nodebay…", for: item)
            let outputItems = try result.files.map { ShelfItem(kind: .file(bookmark: try Bookmark(url: $0).data)) }
            let completed = outputItems.count == 1 ? outputItems[0] : ShelfItem(kind: .stack(name: "\(inspection.title) Downloads", members: outputItems))
            shelf.replaceReference(item, with: [completed])
            update(item.id) { $0.state = .completed; $0.progress = 1 }
        } catch is CancellationError { update(item.id) { $0.state = .cancelled } }
        catch {
            update(item.id) { $0.state = .failed; $0.lastError = error.localizedDescription }
            shelf.setConversionProgress("Retry Download", for: item)
            presentFailure(error)
        }
        let failed = jobs[item.id]?.state == .failed
        shelf.finishConverting([item], preservingProgressForFailures: failed)
        tasks[item.id] = nil
    }

    private func receive(_ progress: MediaDownloadProgress, for item: ShelfItem) {
        update(item.id) { $0.state = progress.stage; $0.progress = progress.percentage }
        ShelfStateViewModel.shared.setConversionProgress(progress.percentage.map { "\(Int($0 * 100))%" } ?? "Downloading…", for: item)
    }

    private func chooseOptions(for inspection: MediaInspection) async -> MediaDownloadOptions? {
        let mustAsk = UserDefaults.standard.object(forKey: "nodebay.downloader.askEveryTime") as? Bool ?? true
        if !mustAsk && !inspection.isPlaylist { return .storedDefault }
        let ffmpegAvailable = await MediaDownloaderService.shared.isFFmpegAvailable()
        let defaults = MediaDownloadOptions.storedDefault
        let alert = NSAlert()
        alert.messageText = inspection.title
        let count = inspection.itemCount.map(String.init) ?? "unknown number of"
        let playlist = inspection.isPlaylist ? "\nPlaylist: \(count) items." : ""
        alert.informativeText = "Source: \(inspection.sourceService) • \(inspection.isYouTube ? "YouTube" : "Experimental yt-dlp support")\(playlist)\nChoose the local output format."
        alert.addButton(withTitle: inspection.isPlaylist ? "Download Playlist" : "Download"); alert.addButton(withTitle: "Cancel")
        let format = NSPopUpButton(frame: NSRect(x: 0, y: 64, width: 280, height: 26))
        format.addItems(withTitles: MediaDownloadFormat.allCases.filter { ffmpegAvailable || $0 != .mp3 }.map(\.rawValue)); format.selectItem(withTitle: defaults.format.rawValue)
        let resolution = NSPopUpButton(frame: NSRect(x: 0, y: 34, width: 135, height: 26)); resolution.addItems(withTitles: ["Best", "2160p", "1440p", "1080p", "720p"]); resolution.selectItem(withTitle: defaults.maximumVideoHeight.map { "\($0)p" } ?? "Best")
        let bitrate = NSPopUpButton(frame: NSRect(x: 145, y: 34, width: 135, height: 26)); bitrate.addItems(withTitles: ["Best", "320 kbps", "256 kbps", "192 kbps", "128 kbps"]); bitrate.selectItem(withTitle: defaults.audioBitrate.map { "\($0) kbps" } ?? "Best")
        let remember = NSButton(checkboxWithTitle: "Use as my default and download automatically", target: nil, action: nil); remember.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 94)); [format, resolution, bitrate, remember].forEach(accessory.addSubview); alert.accessoryView = accessory
        SharingStateManager.shared.beginInteraction()
        defer { SharingStateManager.shared.endInteraction() }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let chosen = MediaDownloadOptions(format: MediaDownloadFormat(rawValue: format.titleOfSelectedItem ?? "") ?? .bestOriginal, maximumVideoHeight: Int((resolution.titleOfSelectedItem ?? "").prefix { $0.isNumber }), audioBitrate: Int((bitrate.titleOfSelectedItem ?? "").prefix { $0.isNumber }))
        if remember.state == .on { chosen.saveAsDefault() }
        return chosen
    }

    private func presentFailure(_ error: Error) {
        SharingStateManager.shared.beginInteraction()
        defer { SharingStateManager.shared.endInteraction() }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func configuredDownloadDirectory() -> URL {
        if let data = UserDefaults.standard.data(forKey: "nodebay.downloader.directoryBookmark"), let url = Bookmark(data: data).resolvedURL { return url }
        return (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")).appending(path: "Nodebay", directoryHint: .isDirectory)
    }
    private func update(_ id: UUID, _ change: (inout MediaDownloadJob) -> Void) { guard var job = jobs[id] else { return }; change(&job); jobs[id] = job; persist() }
    private func persist() { if let data = try? JSONEncoder().encode(jobs.values.sorted { $0.id.uuidString < $1.id.uuidString }) { UserDefaults.standard.set(data, forKey: persistenceKey) } }
}
