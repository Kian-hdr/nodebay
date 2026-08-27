//
//  MusicManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 03/08/24.
//
import AppKit
import Combine
import Defaults
import SwiftUI

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

private enum CurrentMediaDownloadError: LocalizedError {
    case noYouTubeTab, noMatchingYouTubeTab, ambiguousYouTubeTabs

    var errorDescription: String? {
        switch self {
        case .noYouTubeTab:
            "No open YouTube or YouTube Music tab could be read from Chrome."
        case .noMatchingYouTubeTab:
            "No open YouTube tab matched the item currently shown in Now Playing."
        case .ambiguousYouTubeTabs:
            "More than one YouTube tab matched this title. Select the exact browser tab from Nodebay's media-source menu and try again."
        }
    }
}

class MusicManager: ObservableObject {
    enum MediaSourceID: Hashable, Identifiable {
        case controller(MediaControllerType)
        case browserTab(String)

        var id: String {
            switch self {
            case .controller(let type): "controller:\(type.rawValue)"
            case .browserTab(let id): "browser:\(id)"
            }
        }
    }

    struct MediaSourceChoice: Identifiable {
        let id: MediaSourceID
        let displayName: String
        let title: String
        let artist: String
        let bundleIdentifier: String?
        let isPlaying: Bool
        let isAvailable: Bool
        let controllerType: MediaControllerType?
    }

    struct MediaSourceState: Identifiable {
        let type: MediaControllerType
        let title: String
        let artist: String
        let bundleIdentifier: String?
        let isPlaying: Bool
        let isAvailable: Bool

        var id: String { type.rawValue }
    }

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables: [MediaControllerType: Set<AnyCancellable>] = [:]
    private var browserControllers: [String: BrowserTabMediaController] = [:]
    private var browserControllerCancellables: [String: Set<AnyCancellable>] = [:]
    private var debounceIdleTask: Task<Void, Never>?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var controllers: [MediaControllerType: any MediaControllerProtocol] = [:]
    private var activeController: (any MediaControllerProtocol)?
    @Published private(set) var mediaSourceStates: [MediaControllerType: MediaSourceState] = [:]
    @Published private(set) var activeSourceType: MediaControllerType = Defaults[.mediaController]
    @Published private(set) var activeSourceID: MediaSourceID = .controller(Defaults[.mediaController])
    @Published private(set) var browserMediaSessions: [BrowserMediaSession] = []

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var animations: BoringAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var audioCaptureBundleIdentifiers: [String] = []
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Double = 0.5
    @Published var volumeControlSupported: Bool = true
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published var canFavoriteTrack: Bool = false
    @Published private(set) var isResolvingCurrentMediaDownload = false
    
    // Lyrics are now managed by LyricsService
    var lyricsService: LyricsService { LyricsService.shared }
    var currentLyrics: String { lyricsService.currentLyrics }
    var isFetchingLyrics: Bool { lyricsService.isFetchingLyrics }
    var syncedLyrics: [(time: Double, text: String)] { lyricsService.syncedLyrics }
    @Published var isFavoriteTrack: Bool = false

    private var artworkData: Data? = nil

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var isFlipping: Bool = false
    private var flipWorkItem: DispatchWorkItem?

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?

    // MARK: - Initialization
    init() {
        BrowserMediaBridge.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.syncBrowserSessions(sessions)
            }
            .store(in: &cancellables)

        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Initialize the active controller after deprecation check
            self.setActiveControllerBasedOnPreference()
        }
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        browserControllerCancellables.removeAll()
        flipWorkItem?.cancel()
        transitionWorkItem?.cancel()

        // Stop child processes before releasing controller ownership. Waiting
        // for deinit is insufficient when an asynchronous stream is active.
        for controller in controllers.values {
            (controller as? NowPlayingController)?.shutdown()
        }

        activeController = nil
        controllers.removeAll()
        browserControllers.removeAll()
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        if let existing = controllers[type] { return existing }
        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controllers[type] = controller
            controllerCancellables[type] = []
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self else { return }
                    self.mediaSourceStates[type] = MediaSourceState(
                        type: type,
                        title: state.title,
                        artist: state.artist,
                        bundleIdentifier: state.bundleIdentifier,
                        isPlaying: state.isPlaying,
                        isAvailable: controller.isActive()
                    )
                    if self.activeSourceID == .controller(type) {
                        self.updateFromPlaybackState(state)
                    }
                }
                .store(in: &controllerCancellables[type, default: []])
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        initializeMediaSourceRegistry()

        if let controller = createController(for: controllerType) {
            setActiveController(controller, type: controllerType)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController, type: .appleMusic)
        }
    }

    private func initializeMediaSourceRegistry() {
        for type in MediaControllerType.allCases where !(type == .nowPlaying && isNowPlayingDeprecated) {
            guard let controller = createController(for: type) else { continue }
            mediaSourceStates[type] = mediaSourceStates[type] ?? MediaSourceState(
                type: type,
                title: "",
                artist: "",
                bundleIdentifier: type.expectedBundleIdentifier,
                isPlaying: false,
                isAvailable: controller.isActive()
            )
            // Do not query inactive app-specific controllers during startup.
            // AppleScript can otherwise ask the user to locate an application
            // (notably Spotify) even when that application is not installed.
            if controller.isActive() {
                Task { await controller.updatePlaybackInfo() }
            }
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol, type: MediaControllerType) {
        // Cancel any existing flip animation
        flipWorkItem?.cancel()

        // Set new active controller
        activeController = controller
        activeSourceType = type
        activeSourceID = .controller(type)
        
        self.canFavoriteTrack = controller.supportsFavorite

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    func selectMediaSource(_ type: MediaControllerType) {
        guard !(type == .nowPlaying && isNowPlayingDeprecated),
              let controller = createController(for: type) else { return }
        Defaults[.mediaController] = type
        setActiveController(controller, type: type)
    }

    @MainActor
    func selectMediaSource(_ id: MediaSourceID) {
        switch id {
        case .controller(let type):
            selectMediaSource(type)
        case .browserTab(let sessionID):
            guard let controller = browserControllers[sessionID], controller.isActive() else { return }
            flipWorkItem?.cancel()
            activeController = controller
            activeSourceID = .browserTab(sessionID)
            canFavoriteTrack = false
            volumeControlSupported = controller.supportsVolumeControl
            updateFromPlaybackState(controller.session.playbackState)
        }
    }

    var activeSourceLabel: String {
        switch activeSourceID {
        case .controller(let type):
            return type.localizedString
        case .browserTab(let id):
            return browserMediaSessions.first(where: { $0.id == id })?.displayName ?? "Browser tab"
        }
    }

    /// Prefer the exact selected browser-tab URL. When System Now Playing is
    /// active, accept only one title-matched browser session so multiple open
    /// YouTube tabs can never silently resolve to the wrong download.
    var activeDownloadableURL: URL? {
        if case .browserTab(let id) = activeSourceID {
            return browserMediaSessions.first(where: { $0.id == id })?.pageURL.flatMap(Self.downloadableYouTubeMediaURL)
        }
        let target = Self.normalizedMediaTitle(songTitle)
        guard !target.isEmpty else { return nil }
        let matches = browserMediaSessions.compactMap { session -> URL? in
            guard let url = session.pageURL.flatMap(Self.downloadableYouTubeMediaURL) else { return nil }
            let candidate = Self.normalizedMediaTitle(session.title)
            guard candidate == target || candidate.contains(target) || target.contains(candidate) else { return nil }
            return url
        }
        return matches.count == 1 ? matches[0] : nil
    }

    var canDownloadActiveMedia: Bool {
        activeDownloadableURL != nil || (
            bundleIdentifier == "com.google.Chrome" &&
            !songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    @MainActor
    func downloadActiveMediaToNodebay() async {
        guard canDownloadActiveMedia, !isResolvingCurrentMediaDownload else { return }
        isResolvingCurrentMediaDownload = true
        defer { isResolvingCurrentMediaDownload = false }

        do {
            let url: URL
            if let activeDownloadableURL {
                url = activeDownloadableURL
            } else {
                do {
                    url = try await Self.resolveChromeYouTubeURL(matching: songTitle)
                } catch let error as CurrentMediaDownloadError {
                    switch error {
                    case .noYouTubeTab, .noMatchingYouTubeTab:
                        url = try await MediaDownloaderService.shared.resolveYouTubeSearchURL(
                            title: songTitle,
                            artist: artistName
                        )
                    case .ambiguousYouTubeTabs:
                        throw error
                    }
                }
            }
            DownloadCoordinator.shared.add(urls: [url])
            BoringViewCoordinator.shared.currentView = .shelf
        } catch {
            SharingStateManager.shared.beginInteraction()
            defer { SharingStateManager.shared.endInteraction() }
            let alert = NSAlert()
            if Self.isAppleEventsAuthorizationError(error) {
                alert.messageText = "Allow Nodebay to Read the YouTube Tab"
                alert.informativeText = "macOS blocked Nodebay from asking Google Chrome for the current YouTube URL. Allow Chrome under System Settings > Privacy & Security > Automation, then try again."
                alert.addButton(withTitle: "Open Automation Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn,
                   let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(settingsURL)
                }
            } else {
                alert.messageText = "YouTube Download Unavailable"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private static func isAppleEventsAuthorizationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == AppleScriptHelper.errorDomain else { return false }
        if nsError.code == -1743 { return true }
        let message = nsError.localizedDescription.lowercased()
        return message.contains("not authorized")
            || message.contains("not permitted")
            || message.contains("not allowed assistive access")
    }

    private static func resolveChromeYouTubeURL(matching title: String) async throws -> URL {
        let script = """
        tell application "Google Chrome"
            set recordSeparator to ASCII character 30
            set fieldSeparator to ASCII character 31
            set resultText to ""
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL starts with "https://www.youtube.com/" or tabURL starts with "https://music.youtube.com/" then
                        set resultText to resultText & (title of browserTab) & fieldSeparator & tabURL & recordSeparator
                    end if
                end repeat
            end repeat
            return resultText
        end tell
        """
        guard let value = try await AppleScriptHelper.execute(script)?.stringValue else {
            throw CurrentMediaDownloadError.noYouTubeTab
        }
        let target = normalizedMediaTitle(title)
        let candidates: [(title: String, url: URL)] = value
            .split(separator: "\u{001E}", omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(separator: "\u{001F}", maxSplits: 1, omittingEmptySubsequences: false)
                guard fields.count == 2,
                      let rawURL = try? MediaDownloaderService.validatedURL(from: String(fields[1])),
                      let url = downloadableYouTubeMediaURL(rawURL) else { return nil }
                return (String(fields[0]), url)
            }
        let matches = candidates.filter { candidate in
            let normalized = normalizedMediaTitle(candidate.title)
            return normalized == target || normalized.contains(target) || target.contains(normalized)
        }
        if matches.count == 1 { return matches[0].url }
        if matches.count > 1 { throw CurrentMediaDownloadError.ambiguousYouTubeTabs }
        throw CurrentMediaDownloadError.noMatchingYouTubeTab
    }

    private static func downloadableYouTubeMediaURL(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if url.path == "/watch" {
            let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
            return videoID?.isEmpty == false ? url : nil
        }
        let components = url.path.split(separator: "/")
        return components.count == 2 && components[0] == "shorts" && !components[1].isEmpty ? url : nil
    }

    private static func normalizedMediaTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+-\s+YouTube$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var selectableSourceChoices: [MediaSourceChoice] {
        let controllerChoices = selectableMediaSources.map { source in
            MediaSourceChoice(
                id: .controller(source.type),
                displayName: source.type.localizedString,
                title: source.title,
                artist: source.artist,
                bundleIdentifier: source.bundleIdentifier,
                isPlaying: source.isPlaying,
                isAvailable: source.isAvailable,
                controllerType: source.type
            )
        }
        let browserChoices = browserMediaSessions.map { session in
            MediaSourceChoice(
                id: .browserTab(session.id),
                displayName: session.displayName,
                title: session.title,
                artist: session.artist,
                bundleIdentifier: "com.google.Chrome",
                isPlaying: session.isPlaying,
                isAvailable: true,
                controllerType: nil
            )
        }
        return controllerChoices + browserChoices
    }

    var selectableMediaSources: [MediaSourceState] {
        MediaControllerType.allCases.compactMap { type in
            guard !(type == .nowPlaying && isNowPlayingDeprecated) else { return nil }
            if let state = mediaSourceStates[type] {
                return MediaSourceState(
                    type: type,
                    title: state.title,
                    artist: state.artist,
                    bundleIdentifier: state.bundleIdentifier,
                    isPlaying: state.isPlaying,
                    isAvailable: controllers[type]?.isActive() ?? false
                )
            }
            return MediaSourceState(
                type: type,
                title: "",
                artist: "",
                bundleIdentifier: type.expectedBundleIdentifier,
                isPlaying: false,
                isAvailable: false
            )
        }
    }

    private func syncBrowserSessions(_ sessions: [BrowserMediaSession]) {
        browserMediaSessions = sessions
        let currentIDs = Set(sessions.map(\.id))

        for session in sessions {
            if let controller = browserControllers[session.id] {
                controller.update(session: session)
                continue
            }

            let controller = BrowserTabMediaController(session: session)
            browserControllers[session.id] = controller
            browserControllerCancellables[session.id] = []
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self, self.activeSourceID == .browserTab(session.id) else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &browserControllerCancellables[session.id, default: []])
        }

        for id in Set(browserControllers.keys).subtracting(currentIDs) {
            browserControllers[id]?.markUnavailable()
            browserControllers.removeValue(forKey: id)
            browserControllerCancellables.removeValue(forKey: id)
            if activeSourceID == .browserTab(id) {
                setActiveControllerBasedOnPreference()
            }
        }
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        if state.isPlaying != self.isPlaying {
            NSLog("Playback state changed: \(state.isPlaying ? "Playing" : "Paused")")
            withAnimation(.smooth) {
                self.isPlaying = state.isPlaying
                self.updateIdleState(state: state.isPlaying)
            }

            if state.isPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                } else {
                    self.usingAppIconForArtwork = false
                    self.updateAlbumArt(newAlbumArt: defaultImage)
                }
            }
            self.artworkData = state.artwork

            if artworkChanged || state.artwork == nil {
                // Update last artwork change values
                self.lastArtworkTitle = state.title
                self.lastArtworkArtist = state.artist
                self.lastArtworkAlbum = state.album
                self.lastArtworkBundleIdentifier = state.bundleIdentifier
            }

            // Only update sneak peek if there's actual content and something changed
            if !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }

            // Fetch lyrics on content change
            self.fetchLyricsIfAvailable(bundleIdentifier: state.bundleIdentifier, title: state.title, artist: state.artist)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode
        let volumeChanged = state.volume != self.volume
        
        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
            // Update volume control support from active controller
            self.volumeControlSupported = activeController?.supportsVolumeControl ?? false
        }

        let captureBundleIDs = state.effectiveAudioCaptureBundleIdentifiers
        if captureBundleIDs != self.audioCaptureBundleIdentifiers {
            self.audioCaptureBundleIdentifiers = captureBundleIDs
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        if state.isFavorite != self.isFavoriteTrack {
            self.isFavoriteTrack = state.isFavorite
        }
        
        if volumeChanged {
            self.volume = state.volume
        }
        
        self.timestampDate = state.lastUpdated
    }

    func toggleFavoriteTrack() {
        guard canFavoriteTrack else { return }
        // Toggle based on current state
        setFavorite(!isFavoriteTrack)
    }

    @MainActor
    private func toggleAppleMusicFavorite() async {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard !runningApps.isEmpty else { return }

        let script = """
        tell application \"Music\"
            if it is running then
                try
                    set loved of current track to (not loved of current track)
                    return loved of current track
                on error
                    return false
                end try
            else
                return false
            end if
        end tell
        """

        if let result = try? await AppleScriptHelper.execute(script) {
            let loved = result.booleanValue
            self.isFavoriteTrack = loved
            self.forceUpdate()
        }
    }

    func setFavorite(_ favorite: Bool) {
        guard canFavoriteTrack else { return }
        guard let controller = activeController else { return }

        Task { @MainActor in
            await controller.setFavorite(favorite)
            try? await Task.sleep(for: .milliseconds(150))
            await controller.updatePlaybackInfo()
        }
    }

    /// Placeholder dislike function
    func dislikeCurrentTrack() {
        setFavorite(false)
    }

    // MARK: - Lyrics
    private func fetchLyricsIfAvailable(bundleIdentifier: String?, title: String, artist: String) {
        guard Defaults[.enableLyrics], !title.isEmpty else {
            Task { @MainActor in
                lyricsService.clearLyrics()
            }
            return
        }
        
        Task { @MainActor in
            await lyricsService.fetchLyrics(bundleIdentifier: bundleIdentifier, title: title, artist: artist)
        }
    }

    private func triggerFlipAnimation() {
        // Cancel any existing animation
        flipWorkItem?.cancel()

        // Create a new animation
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFlipping = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.isFlipping = false
            }
        }

        flipWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        withAnimation(.smooth) {
            self.albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }
    
    func togglePlay() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func nextTrack() {
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }
    func skip(seconds: TimeInterval) {
        let newPos = min(max(0, elapsedTime + seconds), songDuration)
        seek(to: newPos)
    }
    
    func setVolume(to level: Double) {
        if let controller = activeController {
            Task {
                await controller.setVolume(level)
            }
        }
    }
    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }
    
    
    func syncVolumeFromActiveApp() async {
        // Check if bundle identifier is valid and if the app is actually running
        guard let bundleID = bundleIdentifier, !bundleID.isEmpty,
              NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) else { return }
        
        var script: String?
        if bundleID == "com.apple.Music" {
            script = """
            tell application "Music"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else if bundleID == "com.spotify.client" {
            script = """
            tell application "Spotify"
                if it is running then
                    get sound volume
                else
                    return 50
                end if
            end tell
            """
        } else {
            // For unsupported apps, don't sync volume
            return
        }
        
        if let volumeScript = script,
           let result = try? await AppleScriptHelper.execute(volumeScript) {
            let volumeValue = result.int32Value
            let currentVolume = Double(volumeValue) / 100.0
            
            await MainActor.run {
                if abs(currentVolume - self.volume) > 0.01 {
                    self.volume = currentVolume
                }
            }
        }
    }
}
