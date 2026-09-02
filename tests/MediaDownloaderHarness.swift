import AppKit
import Foundation

// Platform boundaries only are doubled. The real classifier, options, service,
// coordinator, job persistence and shelf-publication path are compiled below.
struct Bookmark {
    let data: Data
    init(url: URL) throws { data = Data(url.absoluteString.utf8) }
    init(data: Data) { self.data = data }
    var resolvedURL: URL? { String(data: data, encoding: .utf8).flatMap(URL.init(string:)) }
}
struct ShelfItem: Identifiable {
    indirect enum Kind { case link(url: URL), file(bookmark: Data), stack(name: String, members: [ShelfItem]) }
    let id = UUID()
    let kind: Kind
}
@MainActor final class ShelfStateViewModel {
    static let shared = ShelfStateViewModel()
    var items: [ShelfItem] = []
    func add(_ items: [ShelfItem]) { self.items += items }
    func beginConverting(_ items: [ShelfItem]) {}
    func finishConverting(_ items: [ShelfItem], preservingProgressForFailures: Bool = false) {}
    func setConversionProgress(_ value: String, for item: ShelfItem) {}
    func replaceReference(_ item: ShelfItem, with items: [ShelfItem]) {
        self.items.removeAll { $0.id == item.id }; self.items += items
    }
}
@MainActor final class SharingStateManager {
    static let shared = SharingStateManager()
    func beginInteraction() {}
    func endInteraction() {}
}
enum NodebayManagedFileStorage {
    enum Kind { case downloads }
    static func directory(for kind: Kind) throws -> URL { FileManager.default.temporaryDirectory }
}
actor XPCHelperClient {
    static let shared = XPCHelperClient()
    func firstAvailableApprovedExecutable(engine: String, candidates: [URL]) -> URL? { candidates.first }
}
enum SafeProcessRunner {
    struct Result { let exitCode: Int32; let standardOutput: String; let standardError: String }
    static func runApproved(engine: String, executable: URL, arguments: [String], timeout: Duration,
                            maximumLogBytes: Int, progress: (@Sendable (MediaDownloadProgress) -> Void)? = nil) async throws -> Result {
        // No network, processes, or user data. Exercise production output
        // promotion/collision checks with a disposable simulated engine output.
        guard let index = arguments.firstIndex(of: "--paths") else {
            return Result(exitCode: 1, standardOutput: "", standardError: "fixture")
        }
        let directory = URL(fileURLWithPath: arguments[index + 1])
        try Data("fixture".utf8).write(to: directory.appendingPathComponent("fixture.mp4"))
        return Result(exitCode: 0, standardOutput: "", standardError: "")
    }
}

actor MockDownloader: MediaDownloading {
    let ffmpeg: Bool
    let root: URL
    var inspected: [URL] = []
    var requests: [(URL, MediaDownloadOptions)] = []
    var fixtures: [String: MediaInspection] = [:]
    var failing: Set<String> = []
    var delay: Duration = .zero
    init(ffmpeg: Bool = true, root: URL) { self.ffmpeg = ffmpeg; self.root = root }
    func configure(_ values: [MediaInspection], failing: Set<String> = [], delay: Duration = .zero) {
        fixtures = Dictionary(uniqueKeysWithValues: values.map { ($0.url.absoluteString, $0) })
        self.failing = failing; self.delay = delay
    }
    func isFFmpegAvailable() -> Bool { ffmpeg }
    func inspect(_ url: URL) throws -> MediaInspection {
        inspected.append(url)
        guard let fixture = fixtures[url.absoluteString] else { throw MediaDownloaderError.noOutput }
        return fixture
    }
    func download(_ inspection: MediaInspection, options: MediaDownloadOptions, destination: URL,
                  playlistConfirmed: Bool, preserveMetadata: Bool, preserveThumbnail: Bool,
                  progress: (@Sendable (MediaDownloadProgress) -> Void)?) async throws -> MediaDownloadResult {
        precondition(options.format != .mp3 || ffmpeg, "MP3 started without FFmpeg")
        requests.append((inspection.url, options))
        if delay != .zero {
            do { try await Task.sleep(for: delay) }
            catch {
                // A late helper callback must not mutate the replacement job.
                progress?(.init(stage: .processing, percentage: 0.9, downloadedBytes: nil, totalBytes: nil, speed: nil, eta: nil))
                throw error
            }
        }
        if failing.contains(inspection.url.absoluteString) { throw MediaDownloaderError.noOutput }
        let file = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(options.format == .mp3 ? "mp3" : "mp4")
        try Data("generated fixture".utf8).write(to: file)
        return MediaDownloadResult(inspection: inspection, files: [file], partialFailure: nil)
    }
}

func fixture(_ address: String, track: String? = nil, artist: String? = nil,
             entries: [MediaInspectionEntry] = [], playlist: Bool = false) -> MediaInspection {
    let url = URL(string: address)!
    return MediaInspection(url: url, title: "Private fixture title", sourceService: "fixture", duration: 1,
                           thumbnailURL: nil, isPlaylist: playlist, itemCount: playlist ? entries.count : nil,
                           classificationMetadata: .init(url: url, categories: [], track: track, artist: artist,
                                                         mediaType: nil, videoCodec: nil, audioCodec: nil), entries: entries)
}

@main struct MediaDownloaderHarness {
    @MainActor static func wait(_ coordinator: DownloadCoordinator) async throws {
        for _ in 0..<500 {
            if !coordinator.jobs.isEmpty && coordinator.jobs.values.allSatisfy({ [.completed, .failed, .cancelled].contains($0.state) }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Coordinator timed out")
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nodebay-coordinator-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "nodebay.test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(MediaDownloadSelectionMode.stored(in: defaults) == .automatic)
        defaults.set("unknown", forKey: "nodebay.downloader.selectionMode")
        precondition(MediaDownloadSelectionMode.stored(in: defaults) == .automatic)
        defaults.set("1080p", forKey: "nodebay.downloader.preferredResolution")
        defaults.set("192 kbps", forKey: "nodebay.downloader.audioBitrate")
        let video = fixture("https://www.youtube.com/watch?v=video")
        let audio = fixture("https://music.youtube.com/watch?v=audio")

        for mode in MediaDownloadSelectionMode.allCases {
            defaults.set(mode.rawValue, forKey: "nodebay.downloader.selectionMode")
            defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
            precondition(MediaDownloadSelectionMode.stored(in: defaults) == mode)
            ShelfStateViewModel.shared.items = []
            let backend = MockDownloader(root: root)
            await backend.configure([video, audio])
            var pickerCount = 0
            let coordinator = DownloadCoordinator(service: backend, defaults: defaults,
                playlistConfirmation: { _ in preconditionFailure("Not a playlist") },
                formatPicker: { _, _ in pickerCount += 1; return .automatic(for: .video, defaults: defaults) },
                failurePresenter: { _ in preconditionFailure("Unexpected download failure") })
            coordinator.add(urls: [video.url, audio.url])
            try await wait(coordinator)
            let requests = await backend.requests
            precondition(requests.count == 2)
            for (url, options) in requests {
                let expected: MediaDownloadFormat = mode == .alwaysAudio || (mode == .automatic && url == audio.url) ? .mp3 : .mp4
                precondition(options.format == expected)
                precondition(options.maximumVideoHeight == 1080 && options.audioBitrate == 192)
            }
            precondition(pickerCount == (mode == .askEveryTime ? 2 : 0))
            precondition(ShelfStateViewModel.shared.items.count == 2)
            for item in ShelfStateViewModel.shared.items {
                guard case .file(let data) = item.kind, let file = Bookmark(data: data).resolvedURL else { preconditionFailure("Output missing from shelf") }
                precondition(FileManager.default.fileExists(atPath: file.path))
            }
            precondition(coordinator.jobs.values.allSatisfy { $0.choiceLabel != nil && $0.classificationReason?.contains("Private") == false })
        }

        // Per-entry inspection, partial success, playlist stack, and safe reports.
        defaults.set(MediaDownloadSelectionMode.automatic.rawValue, forKey: "nodebay.downloader.selectionMode")
        defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
        ShelfStateViewModel.shared.items = []
        let entries = [audio, video].map { MediaInspectionEntry(url: $0.url, title: $0.title, sourceService: $0.sourceService, classificationMetadata: $0.classificationMetadata) }
        let playlist = fixture("https://www.youtube.com/playlist?list=fixture", entries: entries, playlist: true)
        let backend = MockDownloader(root: root)
        await backend.configure([playlist, audio, video], failing: [video.url.absoluteString])
        var confirmedCount: Int?
        let coordinator = DownloadCoordinator(service: backend, defaults: defaults,
            playlistConfirmation: { confirmedCount = $0.itemCount; return true },
            formatPicker: { _, _ in preconditionFailure("Automatic showed format picker") },
            failurePresenter: { _ in preconditionFailure("Partial success was lost") })
        coordinator.add(urls: [playlist.url])
        try await wait(coordinator)
        precondition(confirmedCount == 2)
        let inspected = await backend.inspected
        precondition(inspected == [playlist.url, audio.url, video.url])
        let formats = await backend.requests.map { $0.1.format }
        precondition(formats == [.mp3, .mp4])
        guard case .stack(_, let members) = ShelfStateViewModel.shared.items.first?.kind else { preconditionFailure("Playlist is not a stack") }
        precondition(members.count == 1)
        precondition(coordinator.jobs.values.first?.lastError?.contains("Private") == false)
        precondition(coordinator.jobs.values.first?.itemClassifications?.map { $0.classification.kind } == [.audio, .video])
        let restored = DownloadCoordinator(service: backend, defaults: defaults)
        precondition(restored.jobs.values.first?.itemClassifications == coordinator.jobs.values.first?.itemClassifications)

        // Declined and empty playlists never start a network download.
        for accepted in [false, true] {
            defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
            ShelfStateViewModel.shared.items = []
            let empty = fixture("https://youtube.com/playlist?list=empty", playlist: true)
            let emptyBackend = MockDownloader(root: root)
            await emptyBackend.configure([empty])
            let emptyCoordinator = DownloadCoordinator(service: emptyBackend, defaults: defaults,
                playlistConfirmation: { _ in accepted }, failurePresenter: { _ in })
            emptyCoordinator.add(urls: [empty.url])
            try await wait(emptyCoordinator)
            let emptyRequests = await emptyBackend.requests
            precondition(emptyRequests.isEmpty)
            precondition(emptyCoordinator.jobs.values.first?.state == (accepted ? .failed : .cancelled))
        }

        // Fixed playlist override intentionally applies one type to the whole playlist.
        defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
        ShelfStateViewModel.shared.items = []
        let fixedBackend = MockDownloader(root: root)
        await fixedBackend.configure([playlist])
        let fixed = DownloadCoordinator(service: fixedBackend, defaults: defaults,
            playlistConfirmation: { _ in true }, failurePresenter: { _ in preconditionFailure("Fixed playlist failed") })
        let fixedLink = ShelfItem(kind: .link(url: playlist.url))
        ShelfStateViewModel.shared.add([fixedLink])
        fixed.override(fixedLink, format: .mp4)
        try await wait(fixed)
        let fixedRequests = await fixedBackend.requests
        precondition(fixedRequests.count == 1 && fixedRequests[0].1.format == .mp4)

        // Cancellation keeps already completed playlist files in a separate stack.
        defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
        ShelfStateViewModel.shared.items = []
        let cancellingBackend = MockDownloader(root: root)
        await cancellingBackend.configure([playlist, audio, video], delay: .milliseconds(100))
        let cancelling = DownloadCoordinator(service: cancellingBackend, defaults: defaults,
            playlistConfirmation: { _ in true }, failurePresenter: { _ in preconditionFailure("Cancellation became a failure") })
        cancelling.add(urls: [playlist.url])
        let cancellingLink = ShelfStateViewModel.shared.items[0]
        for _ in 0..<100 {
            if await cancellingBackend.requests.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        cancelling.cancel(cancellingLink)
        for _ in 0..<100 {
            if ShelfStateViewModel.shared.items.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(cancelling.jobs[cancellingLink.id]?.state == .cancelled)
        precondition(ShelfStateViewModel.shared.items.count == 2)
        guard case .stack(_, let retained) = ShelfStateViewModel.shared.items[1].kind else { preconditionFailure("Partial results not retained") }
        precondition(retained.count == 1)

        // Music playlist entries keep the Music URL even when yt-dlp returns a standard URL.
        let entry = MediaDownloaderService.inspectionEntry(from: ["url": video.url.absoluteString], parentURL: URL(string: "https://music.youtube.com/playlist?list=test")!, parent: [:])!
        precondition(entry.url.host == "music.youtube.com")

        // Missing FFmpeg must fail before a predictable MP3 job starts.
        defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
        ShelfStateViewModel.shared.items = []
        let missing = MockDownloader(ffmpeg: false, root: root)
        await missing.configure([audio, video])
        let missingCoordinator = DownloadCoordinator(service: missing, defaults: defaults, failurePresenter: { _ in })
        missingCoordinator.add(urls: [audio.url, video.url])
        try await wait(missingCoordinator)
        let safeRequests = await missing.requests
        precondition(safeRequests.count == 1 && safeRequests[0].1.format == .mp4)
        precondition(missingCoordinator.jobs.values.contains { $0.state == .failed })

        // One-click override cancels and joins the old task, without changing saved defaults.
        defaults.removeObject(forKey: "nodebay.downloader.jobs.v1")
        ShelfStateViewModel.shared.items = []
        let delayed = MockDownloader(root: root)
        await delayed.configure([video], delay: .milliseconds(150))
        let overriding = DownloadCoordinator(service: delayed, defaults: defaults, failurePresenter: { _ in preconditionFailure("Override failed") })
        overriding.add(urls: [video.url])
        let link = ShelfStateViewModel.shared.items[0]
        for _ in 0..<100 {
            if await !delayed.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        overriding.override(link, format: .mp3)
        try await wait(overriding)
        let overrideRequests = await delayed.requests
        precondition(overrideRequests.map { $0.1.format } == [.mp4, .mp3])
        precondition(MediaDownloadSelectionMode.stored(in: defaults) == .automatic)
        precondition(ShelfStateViewModel.shared.items.count == 1)

        let audioOptions = MediaDownloadOptions.automatic(for: .audio, defaults: defaults)
        precondition(MediaDownloaderService.formatArguments(options: audioOptions, ffmpegAvailable: true).contains("192K"))
        let videoOptions = MediaDownloadOptions.automatic(for: .video, defaults: defaults)
        let limited = MediaDownloaderService.formatArguments(options: videoOptions, ffmpegAvailable: false)
        precondition(limited == ["--format", "best[ext=mp4][height<=1080]"])
        precondition(MediaDownloaderService.formatArguments(options: .init(format: .mp3), ffmpegAvailable: true).contains("0"))
        audioOptions.saveAsDefault(in: defaults)
        precondition(MediaDownloadSelectionMode.stored(in: defaults) == .alwaysAudio)
        defaults.set("999999p", forKey: "nodebay.downloader.preferredResolution")
        precondition(MediaDownloadOptions.stored(in: defaults).maximumVideoHeight == nil)

        // Execute the production output-promotion path twice; original is never overwritten.
        let original = root.appendingPathComponent("fixture.mp4")
        try Data("original".utf8).write(to: original)
        let service = MediaDownloaderService()
        let first = try await service.download(video, options: videoOptions, destination: root, playlistConfirmed: false, preserveMetadata: false, preserveThumbnail: false)
        let second = try await service.download(video, options: videoOptions, destination: root, playlistConfirmed: false, preserveMetadata: false, preserveThumbnail: false)
        precondition(first.files[0] != second.files[0] && first.files[0] != original)
        let originalBytes = try Data(contentsOf: original)
        precondition(originalBytes == Data("original".utf8))
        print("Downloader coordinator fixtures passed")
    }
}
