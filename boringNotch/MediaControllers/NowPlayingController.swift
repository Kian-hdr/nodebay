//
//  NowPlayingController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        // A missed/crashed helper must not require restarting Nodebay. The
        // stream delivers metadata; favorite lookup is not a discovery refresh.
        await setupNowPlayingObserver()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: ""
    )

    private(set) var playbackIssue: String?

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier
        
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.executeVoid(script)
            }
        }
        
        // Favorite state is not included in the generic adapter payload.
        try? await Task.sleep(for: .milliseconds(150))
        await fetchFavoriteStateIfSupported()
    }

    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private let adapterResources: MediaRemoteAdapterResources?
    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var observerID: UUID?
    private var restartAttempt = 0
    private let lifecycleLock = NSLock()
    private var isShuttingDown = false

    // MARK: - Initialization
    init?(adapterResources: MediaRemoteAdapterResources? = .bundled) {
        self.adapterResources = adapterResources
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        shutdown()
    }

    /// Stops the adapter explicitly instead of relying on deinitialization at
    /// application termination. The stream task intentionally does not retain
    /// this controller, so clearing the media registry can release everything.
    func shutdown() {
        lifecycleLock.lock()
        guard !isShuttingDown else {
            lifecycleLock.unlock()
            return
        }
        isShuttingDown = true
        let task = streamTask
        let restart = restartTask
        let handler = pipeHandler
        let childProcess = process
        streamTask = nil
        restartTask = nil
        observerID = nil
        pipeHandler = nil
        process = nil
        lifecycleLock.unlock()

        task?.cancel()
        restart?.cancel()
        if childProcess?.isRunning == true {
            childProcess?.terminate()
        }
        if let handler {
            Task { await handler.close() }
        }
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        playbackState.hasMedia && NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == playbackState.bundleIdentifier
        }
    }
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
        }
        
        playbackState.volume = clampedLevel
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let reservation: (UUID, Process)? = lifecycleLock.withLock {
            guard !isShuttingDown, process == nil, restartTask == nil else { return nil }
            let id = UUID()
            let child = Process()
            observerID = id
            process = child
            return (id, child)
        }
        guard let (id, child) = reservation else { return }

        guard let adapterResources,
              FileManager.default.fileExists(atPath: adapterResources.scriptURL.path),
              FileManager.default.fileExists(atPath: adapterResources.frameworkURL.appendingPathComponent("MediaRemoteAdapter").path)
        else {
            await observerEnded(id: id, canRetry: false)
            return
        }
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Full snapshots distinguish an omitted field from a field removed by
        // the media app. They also recover after an interrupted stream.
        child.arguments = [adapterResources.scriptURL.path, adapterResources.frameworkURL.path,
                           "stream", "--no-diff", "--allow-missing-title"]
        child.standardInput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        let handler = JSONLinesPipeHandler()
        let outputPipe = await handler.getPipe()
        child.standardOutput = outputPipe

        let launched = lifecycleLock.withLock {
            guard !isShuttingDown, observerID == id else { return false }
            do {
                try child.run()
                try? outputPipe.fileHandleForWriting.close()
            } catch {
                return false
            }
            pipeHandler = handler
            streamTask = Task { [weak self, handler] in
                await handler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                    await self?.handleStreamUpdate(update, id: id)
                }
                await handler.close()
                await self?.observerEnded(id: id, canRetry: true)
            }
            return true
        }
        if !launched {
            await handler.close()
            await observerEnded(id: id, canRetry: true)
        }
    }

    private func observerEnded(id: UUID, canRetry: Bool) async {
        let shouldReport = lifecycleLock.withLock {
            guard !isShuttingDown, observerID == id else { return false }
            if process?.isRunning == true { process?.terminate() }
            process = nil
            pipeHandler = nil
            streamTask = nil
            observerID = nil
            if canRetry {
                restartAttempt = min(restartAttempt + 1, 6)
                let delay = min(pow(2, Double(restartAttempt - 1)), 30)
                restartTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                    guard let self else { return }
                    self.lifecycleLock.withLock { self.restartTask = nil }
                    await self.setupNowPlayingObserver()
                }
            }
            return true
        }
        guard shouldReport else { return }
        await MainActor.run {
            self.playbackIssue = canRetry
                ? "System Now Playing disconnected. Nodebay is reconnecting automatically."
                : "System Now Playing is missing a bundled component. Reinstall the current Nodebay release."
            self.playbackState = PlaybackState(bundleIdentifier: "")
        }
    }

    // MARK: - Update Methods
    private func handleStreamUpdate(_ update: NowPlayingUpdate, id: UUID) async {
        let current = lifecycleLock.withLock {
            let current = !isShuttingDown && observerID == id
            if current { restartAttempt = 0 }
            return current
        }
        guard current else { return }
        await handleAdapterUpdate(update)
    }

    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let isDiff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        let resolvedBundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (isDiff ? self.playbackState.bundleIdentifier : "")
        )
        let resolvedProcessIdentifier = payload.processIdentifier ?? (isDiff ? playbackState.processIdentifier : nil)
        let sameOwner = resolvedBundleIdentifier == playbackState.bundleIdentifier
            && resolvedProcessIdentifier == playbackState.processIdentifier
        let diff = isDiff && sameOwner
        let captureBundleFallbackIdentifiers: [String]
        if diff {
            captureBundleFallbackIdentifiers =
                resolvedBundleIdentifier != self.playbackState.bundleIdentifier
                ? [resolvedBundleIdentifier]
                : self.playbackState.effectiveAudioCaptureBundleIdentifiers
        } else {
            captureBundleFallbackIdentifiers = [resolvedBundleIdentifier]
        }
        let captureBundleIdentifiers = Self.audioCaptureBundleIdentifiers(
            sourceBundleIdentifier: payload.bundleIdentifier,
            fallbackBundleIdentifiers: captureBundleFallbackIdentifiers
        )
        
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
        
        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            newPlaybackState.artwork = diff ? self.playbackState.artwork : nil
        }

        if let dateString = payload.timestamp,
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = resolvedBundleIdentifier
        newPlaybackState.processIdentifier = resolvedProcessIdentifier
        // Keep a known untitled session when it pauses, but never create one
        // from a player that merely registers an idle Now Playing client.
        newPlaybackState.hasUntitledMediaSession = !resolvedBundleIdentifier.isEmpty
            && newPlaybackState.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (newPlaybackState.isPlaying || (sameOwner && playbackState.hasUntitledMediaSession))
        newPlaybackState.audioCaptureBundleIdentifiers = captureBundleIdentifiers
        
        newPlaybackState.volume = payload.volume ?? (diff ? self.playbackState.volume : 0.5)
        
        let snapshot = newPlaybackState
        await MainActor.run {
            self.playbackIssue = nil
            self.playbackState = snapshot
        }
        
        // Fetch favorite state for supported apps asynchronously
        // await fetchFavoriteStateIfSupported()
    }
    
     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         }
     }
    
}

private extension NowPlayingController {
    static func audioCaptureBundleIdentifiers(
        sourceBundleIdentifier: String?,
        fallbackBundleIdentifiers: [String]
    ) -> [String] {
        let preferred = sourceBundleIdentifier.map { [$0] } ?? fallbackBundleIdentifiers
        return preferred.normalizedBundleIdentifiers
    }
}

struct MediaRemoteAdapterResources {
    let scriptURL: URL
    let frameworkURL: URL

    static var bundled: MediaRemoteAdapterResources? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        return Self(scriptURL: script, frameworkURL: frameworks.appendingPathComponent("MediaRemoteAdapter.framework"))
    }
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
    let processIdentifier: Int32?
    let volume: Double?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private let chunks: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private var buffer = Data()
    private var closed = false

    init() {
        pipe = Pipe()
        fileHandle = pipe.fileHandleForReading
        let pair = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(64))
        chunks = pair.stream
        continuation = pair.continuation
        let continuation = pair.continuation
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                if case .dropped = continuation.yield(data) {
                    // Lost bytes cannot be decoded reliably. Finish this
                    // stream so the owner restarts with a full snapshot.
                    handle.readabilityHandler = nil
                    continuation.finish()
                }
            }
        }
    }

    func getPipe() -> Pipe { pipe }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        for await data in chunks {
            guard !Task.isCancelled else { break }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if let decoded = try? JSONDecoder().decode(type, from: line) { await onLine(decoded) }
            }
            // A malformed helper must not grow the app indefinitely.
            guard buffer.count <= 16 * 1024 * 1024 else { break }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        fileHandle.readabilityHandler = nil
        continuation.finish()
        try? fileHandle.close()
        try? pipe.fileHandleForWriting.close()
    }
}
