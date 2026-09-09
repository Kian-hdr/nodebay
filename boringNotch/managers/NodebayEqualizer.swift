import AVFoundation
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// QuickTime does not consistently publish local-file playback through the
/// system Now Playing feed, so Nodebay reads its public scripting interface.
/// Only playback state is read; media contents never leave the Mac.
final class QuickTimeController: MediaControllerProtocol {
    static let bundleIdentifier = "com.apple.QuickTimePlayerX"

    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(
        PlaybackState(bundleIdentifier: bundleIdentifier)
    )
    private var refreshTimer: Timer?
    private var refreshInFlight = false
    private(set) var playbackIssue: String?

    init() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.updatePlaybackInfo() }
        }
        Task { [weak self] in await self?.updatePlaybackInfo() }
    }

    deinit { refreshTimer?.invalidate() }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { false }

    func setFavorite(_ favorite: Bool) async {}
    func play() async { await executeDocumentCommand("play") }
    func pause() async { await executeDocumentCommand("pause") }
    func togglePlay() async { stateSubject.value.isPlaying ? await pause() : await play() }
    func nextTrack() async {}
    func previousTrack() async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}

    func seek(to time: Double) async {
        await setDocumentProperty("current time", value: String(max(0, time)))
    }

    func setVolume(_ level: Double) async {
        await setDocumentProperty("audio volume", value: String(min(1, max(0, level))))
    }

    func isActive() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    @MainActor
    func updatePlaybackInfo() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        guard isActive() else {
            playbackIssue = nil
            publishUnavailable()
            return
        }

        let script = """
        tell application id "com.apple.QuickTimePlayerX"
            if (count of documents) is 0 then return {}
            set targetDocument to front document
            try
                set targetDocument to document of front window
            end try
            repeat with candidateDocument in documents
                if playing of candidateDocument then
                    set targetDocument to candidateDocument
                    exit repeat
                end if
            end repeat
            tell targetDocument
                return {name, playing, current time, duration, audio volume}
            end tell
        end tell
        """

        do {
            let descriptor = try await AppleScriptHelper.execute(script)
            playbackIssue = nil
            guard let descriptor, let snapshot = Self.parseSnapshot(descriptor) else {
                publishUnavailable()
                return
            }
            stateSubject.send(PlaybackState(
                bundleIdentifier: Self.bundleIdentifier,
                audioCaptureBundleIdentifiers: [Self.bundleIdentifier],
                isPlaying: snapshot.isPlaying,
                title: snapshot.title,
                artist: "QuickTime Player",
                album: "Local media",
                currentTime: snapshot.currentTime,
                duration: snapshot.duration,
                playbackRate: snapshot.isPlaying ? 1 : 0,
                lastUpdated: Date(),
                volume: snapshot.volume
            ))
        } catch {
            playbackIssue = MediaPlaybackIssue.message(for: error, applicationName: "QuickTime Player")
            publishUnavailable()
        }
    }

    private func executeDocumentCommand(_ command: String) async {
        guard command == "play" || command == "pause" else { return }
        try? await AppleScriptHelper.executeVoid("""
        tell application id "com.apple.QuickTimePlayerX"
            if (count of documents) is 0 then return
            set targetDocument to front document
            try
                set targetDocument to document of front window
            end try
            repeat with candidateDocument in documents
                if playing of candidateDocument then
                    set targetDocument to candidateDocument
                    exit repeat
                end if
            end repeat
            \(command) targetDocument
        end tell
        """)
        await updatePlaybackInfo()
    }

    private func setDocumentProperty(_ property: String, value: String) async {
        guard property == "current time" || property == "audio volume", Double(value) != nil else { return }
        try? await AppleScriptHelper.executeVoid("""
        tell application id "com.apple.QuickTimePlayerX"
            if (count of documents) is 0 then return
            set targetDocument to front document
            try
                set targetDocument to document of front window
            end try
            repeat with candidateDocument in documents
                if playing of candidateDocument then
                    set targetDocument to candidateDocument
                    exit repeat
                end if
            end repeat
            set \(property) of targetDocument to \(value)
        end tell
        """)
        await updatePlaybackInfo()
    }

    private func publishUnavailable() {
        guard !stateSubject.value.title.isEmpty || stateSubject.value.isPlaying else { return }
        stateSubject.send(PlaybackState(
            bundleIdentifier: Self.bundleIdentifier,
            title: "",
            artist: "",
            album: "",
            playbackRate: 0
        ))
    }

    struct Snapshot: Equatable {
        let title: String
        let isPlaying: Bool
        let currentTime: Double
        let duration: Double
        let volume: Double
    }

    static func parseSnapshot(_ descriptor: NSAppleEventDescriptor) -> Snapshot? {
        guard descriptor.numberOfItems == 5,
              let title = descriptor.atIndex(1)?.stringValue,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let playing = descriptor.atIndex(2),
              let currentTime = descriptor.atIndex(3),
              let duration = descriptor.atIndex(4),
              let volume = descriptor.atIndex(5) else { return nil }
        return Snapshot(
            title: title,
            isPlaying: playing.booleanValue,
            currentTime: max(0, currentTime.doubleValue),
            duration: max(0, duration.doubleValue),
            volume: min(1, max(0, volume.doubleValue))
        )
    }
}

enum NodebayLocalAudioError: LocalizedError {
    case unsupported
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupported: "Nodebay can play MP3, M4A, WAV, AIFF, and CAF audio files."
        case .unreadable: "The audio file could not be opened. The original file was not changed."
        }
    }
}

final class NodebayLocalAudioController: NSObject, MediaControllerProtocol {
    static let shared = NodebayLocalAudioController()
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "wave", "aif", "aiff", "caf"]

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let equalizer = AVAudioUnitEQ(numberOfBands: NodebayEqualizerProfile.frequencies.count)
    private let stateSubject = CurrentValueSubject<PlaybackState, Never>(
        PlaybackState(bundleIdentifier: Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch")
    )
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var securityScopedURL: URL?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var pausedFrame: AVAudioFramePosition = 0
    private var timer: Timer?
    private var volumeLevel: Float = 1
    private var scheduleGeneration = 0

    override private init() {
        super.init()
        engine.attach(player)
        engine.attach(equalizer)
        engine.connect(player, to: equalizer, format: nil)
        engine.connect(equalizer, to: engine.mainMixerNode, format: nil)
        configureBands()
        equalizer.bypass = true
    }

    deinit {
        stopAndReleaseFile()
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { stateSubject.eraseToAnyPublisher() }
    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { false }

    static func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func loadAndPlay(_ url: URL) throws {
        guard Self.supports(url) else { throw NodebayLocalAudioError.unsupported }
        stopAndReleaseFile()
        let didAccess = url.startAccessingSecurityScopedResource()
        do {
            let audioFile = try AVAudioFile(forReading: url)
            file = audioFile
            fileURL = url
            securityScopedURL = didAccess ? url : nil
            pausedFrame = 0
            try ensureEngineRunning()
            schedule(from: 0, play: true)
            startTimer()
            publish(isPlaying: true)
        } catch {
            if didAccess { url.stopAccessingSecurityScopedResource() }
            file = nil
            fileURL = nil
            securityScopedURL = nil
            throw NodebayLocalAudioError.unreadable
        }
    }

    func apply(profile: NodebayEqualizerProfile, bypassed: Bool) {
        for (index, band) in equalizer.bands.enumerated() {
            band.gain = profile.gains[index]
            band.bypass = false
        }
        equalizer.globalGain = profile.headroom
        equalizer.bypass = bypassed
    }

    func setFavorite(_ favorite: Bool) async {}
    func play() async {
        guard file != nil, !player.isPlaying else { return }
        do {
            try ensureEngineRunning()
            schedule(from: pausedFrame, play: true)
            publish(isPlaying: true)
        } catch {}
    }
    func pause() async {
        guard player.isPlaying else { return }
        pausedFrame = currentFrame
        scheduleGeneration += 1
        player.stop()
        publish(isPlaying: false)
    }
    func seek(to time: Double) async {
        guard let file else { return }
        let target = min(max(0, time), duration)
        let frame = AVAudioFramePosition(target * file.processingFormat.sampleRate)
        pausedFrame = frame
        schedule(from: frame, play: stateSubject.value.isPlaying)
        publish(isPlaying: player.isPlaying)
    }
    func nextTrack() async {}
    func previousTrack() async {}
    func togglePlay() async { player.isPlaying ? await pause() : await play() }
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async {
        volumeLevel = min(1, max(0, Float(level)))
        player.volume = volumeLevel
        publish(isPlaying: player.isPlaying)
    }
    func isActive() -> Bool { file != nil }
    func updatePlaybackInfo() async { publish(isPlaying: player.isPlaying) }

    private var duration: Double {
        guard let file, file.processingFormat.sampleRate > 0 else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private var currentFrame: AVAudioFramePosition {
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return pausedFrame }
        return scheduledStartFrame + playerTime.sampleTime
    }

    private func configureBands() {
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = NodebayEqualizerProfile.frequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
    }

    private func ensureEngineRunning() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func schedule(from frame: AVAudioFramePosition, play shouldPlay: Bool) {
        guard let file else { return }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        player.stop()
        scheduledStartFrame = min(max(0, frame), file.length)
        pausedFrame = scheduledStartFrame
        let remaining = max(0, file.length - scheduledStartFrame)
        guard remaining > 0 else {
            publish(isPlaying: false)
            return
        }
        player.scheduleSegment(
            file,
            startingFrame: scheduledStartFrame,
            frameCount: AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max))),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard self?.scheduleGeneration == generation else { return }
                self?.finishPlayback()
            }
        }
        player.volume = volumeLevel
        if shouldPlay { player.play() }
    }

    private func finishPlayback() {
        guard file != nil else { return }
        pausedFrame = file?.length ?? 0
        publish(isPlaying: false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.publish(isPlaying: self?.player.isPlaying == true)
        }
    }

    private func publish(isPlaying: Bool) {
        guard let file, let fileURL else { return }
        let sampleRate = file.processingFormat.sampleRate
        let elapsed = sampleRate > 0 ? Double(currentFrame) / sampleRate : 0
        stateSubject.send(PlaybackState(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "theboringteam.boringnotch",
            isPlaying: isPlaying,
            title: fileURL.deletingPathExtension().lastPathComponent,
            artist: "Nodebay Local Audio",
            album: "Local file",
            currentTime: min(duration, max(0, elapsed)),
            duration: duration,
            playbackRate: isPlaying ? 1 : 0,
            lastUpdated: Date(),
            volume: Double(volumeLevel)
        ))
    }

    private func stopAndReleaseFile() {
        scheduleGeneration += 1
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        if let securityScopedURL { securityScopedURL.stopAccessingSecurityScopedResource() }
        securityScopedURL = nil
        file = nil
        fileURL = nil
    }
}

/// Inserts Nodebay's EQ into the audible output of another local process.
///
/// First probe with an unmuted tap and silent Nodebay output. Only after actual
/// audio arrives does `.mutedWhenTapped` suppress the original process path and
/// Nodebay route the processed signal. Missing audio or a failed graph restores
/// normal output and exposes recovery instructions.
/// Allocation-free five-band peaking equalizer for Core Audio device callbacks.
/// Coefficients are swapped under a short lock; filter history is owned only by
/// the realtime callback and is never reset while a slider is moving.
final class NodebayRealtimeEqualizer: @unchecked Sendable {
    private struct Coefficients {
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float
    }

    private struct State {
        var z1: Float = 0
        var z2: Float = 0
    }

    private struct Parameters {
        var coefficients: [Coefficients]
        var outputGain: Float
    }

    private let sampleRate: Double
    private let parameterLock = NSLock()
    private var parameters: Parameters
    private var routesOutput = false
    private var health = NodebayProcessAudioHealth()
    private var states = Array(
        repeating: Array(repeating: State(), count: NodebayEqualizerProfile.frequencies.count),
        count: 16
    )

    init(sampleRate: Double, profile: NodebayEqualizerProfile) {
        self.sampleRate = sampleRate
        parameters = Self.parameters(for: profile, sampleRate: sampleRate)
    }

    func update(profile: NodebayEqualizerProfile) {
        let updated = Self.parameters(for: profile, sampleRate: sampleRate)
        parameterLock.lock()
        parameters = updated
        parameterLock.unlock()
    }

    func setRoutesOutput(_ enabled: Bool) {
        parameterLock.lock()
        routesOutput = enabled
        parameterLock.unlock()
    }

    func healthSnapshot() -> NodebayProcessAudioHealth {
        parameterLock.lock()
        defer { parameterLock.unlock() }
        return health
    }

    func process(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>
    ) {
        parameterLock.lock()
        let snapshot = parameters
        let audible = routesOutput
        parameterLock.unlock()

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        // Clear every output, including buffers a malformed input cannot fill.
        for buffer in outputs {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let inputChannels = inputs.reduce(0) { $0 + Int($1.mNumberChannels) }
        let outputChannels = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }
        var valid = inputChannels > 0 && inputChannels <= states.count && inputChannels == outputChannels
        var frames = Int.max
        for buffer in inputs {
            let channels = Int(buffer.mNumberChannels)
            if channels == 0 || buffer.mData == nil { valid = false; continue }
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
        }
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            if channels == 0 || buffer.mData == nil { valid = false; continue }
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
        }
        valid = valid && frames > 0 && frames != Int.max
        var hasSignal = false
        if valid {
            // Match channels rather than buffer indices. Devices can expose
            // one interleaved buffer or separate buffers for each channel.
            var channel = 0
            for inputBuffer in inputs {
                let inputCount = Int(inputBuffer.mNumberChannels)
                let source = inputBuffer.mData!.assumingMemoryBound(to: Float.self)
                for localChannel in 0..<inputCount {
                    var outputChannel = channel
                    var outputIndex = 0
                    while outputChannel >= Int(outputs[outputIndex].mNumberChannels) {
                        outputChannel -= Int(outputs[outputIndex].mNumberChannels)
                        outputIndex += 1
                    }
                    let outputBuffer = outputs[outputIndex]
                    let outputCount = Int(outputBuffer.mNumberChannels)
                    let destination = outputBuffer.mData!.assumingMemoryBound(to: Float.self)
                    for frame in 0..<frames {
                        var value = source[frame * inputCount + localChannel]
                        guard value.isFinite else { valid = false; continue }
                        if abs(value) > 0.0000001 { hasSignal = true }
                        for bandIndex in snapshot.coefficients.indices {
                            let coefficient = snapshot.coefficients[bandIndex]
                            var state = states[channel][bandIndex]
                            let filtered = coefficient.b0 * value + state.z1
                            state.z1 = coefficient.b1 * value - coefficient.a1 * filtered + state.z2
                            state.z2 = coefficient.b2 * value - coefficient.a2 * filtered
                            states[channel][bandIndex] = state
                            value = filtered
                        }
                        if audible { destination[frame * outputCount + outputChannel] = value * snapshot.outputGain }
                    }
                    channel += 1
                }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        parameterLock.lock()
        health.lastCallback = now
        health.invalidLayout = !valid
        if hasSignal && valid { health.lastSignal = now }
        parameterLock.unlock()
    }

    private static func parameters(for profile: NodebayEqualizerProfile, sampleRate: Double) -> Parameters {
        let coefficients = zip(NodebayEqualizerProfile.frequencies, profile.gains).map { frequency, gain in
            peaking(frequency: Double(frequency), gain: Double(gain), sampleRate: sampleRate)
        }
        return Parameters(
            coefficients: coefficients,
            outputGain: pow(10, profile.headroom / 20)
        )
    }

    private static func peaking(frequency: Double, gain: Double, sampleRate: Double) -> Coefficients {
        let amplitude = pow(10, gain / 40)
        let omega = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let alpha = sin(omega) / 2
        let cosine = cos(omega)
        let a0 = 1 + alpha / amplitude
        return Coefficients(
            b0: Float((1 + alpha * amplitude) / a0),
            b1: Float((-2 * cosine) / a0),
            b2: Float((1 - alpha * amplitude) / a0),
            a1: Float((-2 * cosine) / a0),
            a2: Float((1 - alpha / amplitude) / a0)
        )
    }
}

final class NodebayProcessAudioEqualizer {
    static let shared = NodebayProcessAudioEqualizer()

    private let queue = DispatchQueue(label: "com.nodebay.process-equalizer", qos: .userInitiated)
    private var ioProcID: AudioDeviceIOProcID?
    private var realtimeEqualizer: NodebayRealtimeEqualizer?
    private var isProcessing = false
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var activeBundleIdentifiers: [String] = []
    private var activeProfile = NodebayEqualizerProfile(gains: [])
    private var activeOutputDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?
    private var healthTimer: DispatchSourceTimer?
    private var healthGeneration = 0
    private var healthTicks = 0
    private var probeStartedAt: TimeInterval = 0
    private var routesOutput = false
    private var activeProcessObjectIDs: [AudioObjectID] = []
    private var activeSampleRate: Double = 0
    private var tapDescription: CATapDescription?
    private let statusSubject = CurrentValueSubject<NodebayProcessAudioStatus, Never>(.idle)

    var statusPublisher: AnyPublisher<NodebayProcessAudioStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    private init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stopSynchronously()
    }

    func apply(bundleIdentifiers: [String], profile: NodebayEqualizerProfile, bypassed: Bool) {
        let normalized = bundleIdentifiers.normalizedBundleIdentifiers.sorted()
        queue.async { [weak self] in
            guard let self else { return }
            guard !bypassed, !normalized.isEmpty else {
                self.stopOnQueue()
                return
            }
            if self.isProcessing, self.activeBundleIdentifiers == normalized {
                self.activeProfile = profile
                self.realtimeEqualizer?.update(profile: profile)
                return
            }
            self.stopOnQueue()
            guard #available(macOS 14.2, *) else { return }
            do {
                try self.startOnQueue(bundleIdentifiers: normalized, profile: profile)
            } catch {
                self.failOnQueue(error)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.stopOnQueue() }
    }

    @available(macOS 14.2, *)
    private func startOnQueue(bundleIdentifiers: [String], profile: NodebayEqualizerProfile) throws {
        dispatchPrecondition(condition: .onQueue(queue))
        statusSubject.send(.checking)
        let processObjectIDs = try audioProcessObjectIDs(matching: bundleIdentifiers)
        guard !processObjectIDs.isEmpty else { throw ProcessEqualizerError.noAudioProcess }
        let outputDeviceID = try defaultOutputDeviceID()
        let outputDeviceUID = try stringProperty(
            objectID: outputDeviceID,
            selector: kAudioDevicePropertyDeviceUID,
            scope: kAudioObjectPropertyScopeGlobal
        )

        // Capture the stream that is actually feeding the current output
        // device. A generic stereo mixdown uses Core Audio's mix rate (often
        // 48 kHz), which may differ from Bluetooth/AirPlay hardware (commonly
        // 44.1 kHz). Putting those mismatched streams in one aggregate can
        // invalidate AUHAL's input format and stop playback when the graph is
        // started. Core Audio guarantees that a device-scoped tap matches the
        // selected output stream, keeping one coherent format end to end.
        let tapDescription = CATapDescription(
            processes: processObjectIDs,
            deviceUID: outputDeviceUID,
            stream: 0
        )
        tapDescription.name = "Nodebay Process Equalizer"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.isExclusive = false

        var createdTap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTap)
        guard tapStatus == noErr, createdTap != kAudioObjectUnknown else {
            throw ProcessEqualizerError.coreAudio("create process tap", tapStatus)
        }
        tapObjectID = createdTap
        self.tapDescription = tapDescription

        let tapUID = try stringProperty(
            objectID: tapObjectID,
            selector: kAudioTapPropertyUID,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let tapFormat = try audioStreamFormatProperty(
            objectID: tapObjectID,
            selector: kAudioTapPropertyFormat,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Nodebay Process Equalizer",
            kAudioAggregateDeviceUIDKey: "com.nodebay.process-equalizer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceSubDeviceListKey: [[
                kAudioSubDeviceUIDKey: outputDeviceUID,
                kAudioSubDeviceDriftCompensationKey: 0,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: 1,
            ]],
        ]

        var createdAggregate = AudioDeviceID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &createdAggregate
        )
        guard aggregateStatus == noErr, createdAggregate != kAudioObjectUnknown else {
            throw ProcessEqualizerError.coreAudio("create processing device", aggregateStatus)
        }
        aggregateDeviceID = createdAggregate

        guard tapFormat.mFormatID == kAudioFormatLinearPCM,
              tapFormat.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              tapFormat.mBitsPerChannel == 32 else {
            throw ProcessEqualizerError.invalidTapFormat
        }

        // AVAudioEngine reconfigures AUHAL asynchronously when its device is
        // changed. On Bluetooth and AirPlay routes that can briefly expose the
        // previous microphone format, invalidate the graph, and interrupt the
        // source. Core Audio's device IOProc is the supported direct loopback
        // path for an aggregate device: the tap arrives in `inInputData`, the
        // processed frames are written to `outOutputData`, and parameter
        // changes do not rebuild or restart the route.
        let processor = NodebayRealtimeEqualizer(sampleRate: tapFormat.mSampleRate, profile: profile)
        var createdIOProc: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProc,
            aggregateDeviceID,
            nil
        ) { _, inputData, _, outputData, _ in
            processor.process(input: inputData, output: outputData)
        }
        guard ioProcStatus == noErr, let createdIOProc else {
            throw ProcessEqualizerError.coreAudio("create processing callback", ioProcStatus)
        }
        ioProcID = createdIOProc
        realtimeEqualizer = processor
        activeBundleIdentifiers = bundleIdentifiers
        activeProfile = profile
        activeOutputDeviceID = outputDeviceID
        activeProcessObjectIDs = processObjectIDs
        activeSampleRate = try nominalSampleRate(of: outputDeviceID)
        let startStatus = AudioDeviceStart(aggregateDeviceID, createdIOProc)
        guard startStatus == noErr else {
            throw ProcessEqualizerError.coreAudio("start processing device", startStatus)
        }
        isProcessing = true
        probeStartedAt = ProcessInfo.processInfo.systemUptime
        installHealthTimer()

        var outputAddress = Self.defaultOutputPropertyAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.queue.async {
                guard let currentOutput = try? self.defaultOutputDeviceID(),
                      currentOutput != self.activeOutputDeviceID else { return }
                self.rebuildOnQueue()
            }
        }
        let listenerStatus = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            queue,
            listener
        )
        if listenerStatus == noErr {
            outputDeviceListener = listener
        } else {
            NSLog("[NodebayEqualizer] Output-device listener unavailable: \(listenerStatus)")
        }
        NSLog(
            "[NodebayEqualizer] Native process EQ checking input (tap %.0f Hz/%u ch, route %.0f Hz/%u ch)",
            tapFormat.mSampleRate,
            tapFormat.mChannelsPerFrame,
            tapFormat.mSampleRate,
            tapFormat.mChannelsPerFrame
        )
    }

    @available(macOS 14.2, *)
    private func installHealthTimer() {
        healthGeneration += 1
        let generation = healthGeneration
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self, self.healthGeneration == generation, self.isProcessing,
                  let processor = self.realtimeEqualizer else { return }
            do {
                self.healthTicks += 1
                // Process IDs change when Spotify/Chrome replace an audio
                // helper. A sample-rate change can retain the same device ID.
                if self.healthTicks % 4 == 0 {
                    let currentOutput = try self.defaultOutputDeviceID()
                    let processes = try self.audioProcessObjectIDs(matching: self.activeBundleIdentifiers)
                    let sampleRate = try self.nominalSampleRate(of: currentOutput)
                    if currentOutput != self.activeOutputDeviceID || processes != self.activeProcessObjectIDs
                        || sampleRate != self.activeSampleRate {
                        self.rebuildOnQueue()
                        return
                    }
                }
                let now = ProcessInfo.processInfo.systemUptime
                let health = processor.healthSnapshot()
                switch health.decision(now: now, startedAt: self.probeStartedAt, routed: self.routesOutput) {
                case .wait: break
                case .activate:
                    try self.setTapMuted(true)
                    processor.setRoutesOutput(true)
                    self.routesOutput = true
                    self.statusSubject.send(.active)
                    NSLog("[NodebayEqualizer] Native process EQ received audio and is routing processed output")
                case .restore:
                    processor.setRoutesOutput(false)
                    try self.setTapMuted(false)
                    self.routesOutput = false
                    self.probeStartedAt = now
                    self.statusSubject.send(.checking)
                case .fail:
                    throw health.invalidLayout ? ProcessEqualizerError.invalidTapFormat : ProcessEqualizerError.noAudioReceived
                }
            } catch {
                self.failOnQueue(error)
            }
        }
        healthTimer = timer
        timer.resume()
    }

    @available(macOS 14.2, *)
    private func setTapMuted(_ muted: Bool) throws {
        guard let tapDescription else { throw ProcessEqualizerError.engineDidNotStart }
        tapDescription.muteBehavior = muted ? .mutedWhenTapped : .unmuted
        var description = tapDescription
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyDescription,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(tapObjectID, &address, 0, nil,
            UInt32(MemoryLayout<CATapDescription>.size), &description)
        guard status == noErr else { throw ProcessEqualizerError.coreAudio("update the audio route", status) }
    }

    @available(macOS 14.2, *)
    private func rebuildOnQueue() {
        let identifiers = activeBundleIdentifiers
        let profile = activeProfile
        stopOnQueue()
        guard !identifiers.isEmpty else { return }
        do {
            try startOnQueue(bundleIdentifiers: identifiers, profile: profile)
        } catch {
            failOnQueue(error)
        }
    }

    private func failOnQueue(_ error: Error) {
        stopOnQueue()
        statusSubject.send(.unavailable(error.localizedDescription))
        NSLog("[NodebayEqualizer] Native process EQ restored normal audio: \(error.localizedDescription)")
    }

    private func nominalSampleRate(of device: AudioDeviceID) throws -> Double {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        guard status == noErr, rate > 0 else { throw ProcessEqualizerError.unstableTapFormat }
        return rate
    }

    private func stopSynchronously() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync { stopOnQueue() }
        }
    }

    private let queueKey = DispatchSpecificKey<Void>()

    private func stopOnQueue() {
        healthGeneration += 1
        healthTimer?.cancel()
        healthTimer = nil
        healthTicks = 0
        realtimeEqualizer?.setRoutesOutput(false)
        // Restore passthrough before destroying a graph, even when IO stalled.
        if #available(macOS 14.2, *), tapObjectID != kAudioObjectUnknown {
            try? setTapMuted(false)
        }
        routesOutput = false
        statusSubject.send(.idle)
        if let outputDeviceListener {
            var outputAddress = Self.defaultOutputPropertyAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &outputAddress,
                queue,
                outputDeviceListener
            )
            self.outputDeviceListener = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        ioProcID = nil
        realtimeEqualizer = nil
        isProcessing = false
        activeBundleIdentifiers = []
        activeOutputDeviceID = kAudioObjectUnknown
        activeProcessObjectIDs = []
        activeSampleRate = 0

        if aggregateDeviceID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if status != noErr && status != kAudioHardwareBadObjectError {
                NSLog("[NodebayEqualizer] Processing device cleanup failed: \(status)")
            }
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapObjectID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) {
                let status = AudioHardwareDestroyProcessTap(tapObjectID)
                if status != noErr && status != kAudioHardwareBadObjectError {
                    NSLog("[NodebayEqualizer] Process tap cleanup failed: \(status)")
                }
            }
            tapObjectID = kAudioObjectUnknown
            tapDescription = nil
        }
    }

    @available(macOS 14.2, *)
    private func audioProcessObjectIDs(matching bundleIdentifiers: [String]) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            throw ProcessEqualizerError.cannotEnumerateProcesses
        }
        var objectIDs = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objectIDs) == noErr else {
            throw ProcessEqualizerError.cannotEnumerateProcesses
        }
        let applications = Dictionary(uniqueKeysWithValues: bundleIdentifiers.map { identifier in
            (identifier, NSRunningApplication.runningApplications(withBundleIdentifier: identifier))
        })
        return objectIDs.filter { objectID in
            let processBundleID = try? stringProperty(objectID: objectID,
                selector: kAudioProcessPropertyBundleID, scope: kAudioObjectPropertyScopeGlobal)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let hasPID = AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &pid) == noErr
            guard !hasPID || pid != ProcessInfo.processInfo.processIdentifier else { return false }
            let app = hasPID ? NSRunningApplication(processIdentifier: pid) : nil
            let bundlePath = app?.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
            return bundleIdentifiers.contains { requested in
                let roots = (applications[requested] ?? []).compactMap {
                    $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path
                }
                return NodebayAudioProcessIdentity.matches(bundleID: processBundleID,
                    bundlePath: bundlePath, requestedID: requested, applicationPaths: roots)
            }
        }.sorted()
    }

    private func defaultOutputDeviceID() throws -> AudioDeviceID {
        var address = Self.defaultOutputPropertyAddress
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw ProcessEqualizerError.coreAudio("find output device", status)
        }
        return deviceID
    }

    private func audioStreamFormatProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr, value.mChannelsPerFrame > 0, value.mSampleRate > 0 else {
            throw ProcessEqualizerError.coreAudio("read tap format", status)
        }
        return value
    }

    private static var defaultOutputPropertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else {
            throw ProcessEqualizerError.coreAudio("read audio property", status)
        }
        return value as String
    }
}

private enum ProcessEqualizerError: LocalizedError {
    case noAudioProcess
    case cannotEnumerateProcesses
    case noAudioReceived
    case missingOutputUnit
    case invalidTapFormat
    case unstableTapFormat
    case engineDidNotStart
    case coreAudio(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noAudioProcess: "No active audio process was found for this source."
        case .cannotEnumerateProcesses: "Nodebay could not inspect the active audio processes. Retry after starting playback."
        case .noAudioReceived: "No audio received. Start playback on this Mac. If it is already playing, allow Nodebay in System Settings > Privacy & Security > Screen & System Audio Recording, then retry."
        case .missingOutputUnit: "The current output device is unavailable."
        case .invalidTapFormat: "The source audio format is not supported by the current output device."
        case .unstableTapFormat: "The audio route did not become ready in time."
        case .engineDidNotStart: "The audio processing engine did not start."
        case .coreAudio(let operation, let status): "Core Audio could not \(operation) (\(status)). Check Nodebay’s System Audio Recording permission and current sound output, then retry."
        }
    }
}

@MainActor
final class NodebayEqualizerManager: ObservableObject {
    static let shared = NodebayEqualizerManager()

    @Published private(set) var preset: NodebayEqualizerPreset
    @Published private(set) var customGains: [Float]
    @Published private(set) var isBypassed: Bool
    @Published private(set) var processAudioStatus: NodebayProcessAudioStatus = .idle
    private var processStatusSubscription: AnyCancellable?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preset = NodebayEqualizerPreset(
            rawValue: defaults.string(forKey: "nodebay.equalizer.preset") ?? "Flat"
        ) ?? .flat
        customGains = (defaults.array(forKey: "nodebay.equalizer.customGains") as? [NSNumber])?.map(\.floatValue)
            ?? [0, 0, 0, 0, 0]
        isBypassed = defaults.object(forKey: "nodebay.equalizer.bypassed") as? Bool ?? false
        applyToLocalPlayer()
        processStatusSubscription = NodebayProcessAudioEqualizer.shared.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.processAudioStatus = status }
    }

    var profile: NodebayEqualizerProfile {
        .preset(preset, custom: customGains)
    }

    private var isChromeNowPlaying: Bool {
        guard let identifier = MusicManager.shared.bundleIdentifier else { return false }
        return identifier == "com.google.Chrome" || identifier.hasPrefix("com.google.Chrome.")
    }

    private var isQuickTimeNowPlaying: Bool {
        MusicManager.shared.bundleIdentifier == QuickTimeController.bundleIdentifier
    }

    private var isSpotifyNowPlaying: Bool {
        guard let identifier = MusicManager.shared.bundleIdentifier else { return false }
        return NodebayAudioProcessIdentity.matches(bundleID: identifier, bundlePath: nil,
            requestedID: "com.spotify.client", applicationPaths: [])
    }

    func isAvailable(for source: MusicManager.MediaSourceID) -> Bool {
        switch source {
        case .localAudio:
            NodebayLocalAudioController.shared.isActive()
        case .browserTab(let id):
            if #available(macOS 14.2, *) {
                BrowserMediaBridge.shared.sessions.contains(where: { $0.id == id })
            } else {
                false
            }
        case .controller(let type):
            if #available(macOS 14.2, *) {
                if type == .quickTime {
                    !NSRunningApplication.runningApplications(
                        withBundleIdentifier: QuickTimeController.bundleIdentifier
                    ).isEmpty
                } else if type == .spotify {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
                } else if type == .nowPlaying {
                    isChromeNowPlaying || isQuickTimeNowPlaying || isSpotifyNowPlaying
                } else {
                    false
                }
            } else {
                false
            }
        }
    }

    func availabilityMessage(for source: MusicManager.MediaSourceID) -> String {
        switch source {
        case .localAudio:
            return NodebayLocalAudioController.shared.isActive()
                ? "Equalizer processes this file locally."
                : "Play a supported local audio file from the shelf first."
        case .browserTab:
            return isAvailable(for: source)
                ? "Equalizer processes Chrome audio locally through macOS Core Audio."
                : "Select an active Chrome media tab first."
        case .controller(let type):
            if type == .spotify || (type == .nowPlaying && isSpotifyNowPlaying) {
                return isAvailable(for: source)
                    ? "Equalizer processes Spotify audio playing on this Mac."
                    : "Start playback in Spotify on this Mac first."
            }
            if type == .quickTime {
                return isAvailable(for: source)
                    ? "Equalizer processes QuickTime audio locally through macOS Core Audio."
                    : "Start playback in QuickTime Player first."
            }
            if type == .nowPlaying, isChromeNowPlaying {
                return "Equalizer processes Chrome audio locally through macOS Core Audio."
            }
            if type == .nowPlaying, isQuickTimeNowPlaying {
                return "Equalizer processes QuickTime audio locally through macOS Core Audio."
            }
            return "Equalizer unavailable for this source."
        }
    }

    func processingMessage(for source: MusicManager.MediaSourceID) -> String {
        guard isAvailable(for: source) else { return availabilityMessage(for: source) }
        if isBypassed { return "Equalizer off. Original audio plays normally." }
        if MusicManager.shared.activeSourceID == source, !MusicManager.shared.isPlaying {
            return "Paused. Equalizer resumes when playback starts."
        }
        if source == .localAudio { return "Processing this file locally." }
        switch processAudioStatus {
        case .idle: return "Start playback on this Mac to use the equalizer."
        case .checking: return "Checking audio access. Original audio continues playing."
        case .active:
            if case .browserTab = source { return "Processing Chrome audio locally, including other audible Chrome tabs." }
            if source == .controller(.nowPlaying), isChromeNowPlaying {
                return "Processing Chrome audio locally, including other audible Chrome tabs."
            }
            return "Processing audio locally."
        case .unavailable(let message): return message
        }
    }

    func canRetryProcessing(for source: MusicManager.MediaSourceID) -> Bool {
        guard source != .localAudio, isAvailable(for: source), !isBypassed else { return false }
        if MusicManager.shared.activeSourceID == source, !MusicManager.shared.isPlaying { return false }
        if case .unavailable = processAudioStatus { return true }
        return processAudioStatus == .idle
    }

    func retryProcessing(for source: MusicManager.MediaSourceID) {
        NodebayProcessAudioEqualizer.shared.stop()
        apply(to: source)
    }

    func openAudioRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func select(_ newPreset: NodebayEqualizerPreset, source: MusicManager.MediaSourceID) {
        preset = newPreset
        persist()
        apply(to: source)
    }

    func setGain(_ value: Float, band index: Int, source: MusicManager.MediaSourceID) {
        guard customGains.indices.contains(index) else { return }
        if preset != .custom {
            customGains = profile.gains
        }
        customGains[index] = min(NodebayEqualizerProfile.gainRange.upperBound, max(NodebayEqualizerProfile.gainRange.lowerBound, value))
        preset = .custom
        persist()
        apply(to: source)
    }

    func setToneGain(_ value: Float, tone: NodebayEqualizerTone, source: MusicManager.MediaSourceID) {
        let baseProfile = profile
        let clamped = min(NodebayEqualizerProfile.gainRange.upperBound, max(NodebayEqualizerProfile.gainRange.lowerBound, value))
        guard abs(baseProfile.gain(for: tone) - clamped) >= 0.5 else { return }
        customGains = baseProfile.setting(clamped, for: tone).gains
        preset = .custom
        persist()
        apply(to: source)
    }

    func setBypassed(_ bypassed: Bool, source: MusicManager.MediaSourceID) {
        isBypassed = bypassed
        persist()
        apply(to: source)
    }

    func reset(source: MusicManager.MediaSourceID) {
        preset = .flat
        customGains = [0, 0, 0, 0, 0]
        isBypassed = false
        persist()
        apply(to: source)
    }

    func apply(to source: MusicManager.MediaSourceID) {
        switch source {
        case .localAudio:
            NodebayProcessAudioEqualizer.shared.stop()
            applyToLocalPlayer()
        case .browserTab(let id):
            if BrowserMediaBridge.shared.sessions.first(where: { $0.id == id })?.eqEnabled == true {
                BrowserMediaBridge.shared.disableEqualizer(sessionID: id)
            }
            NodebayProcessAudioEqualizer.shared.apply(
                bundleIdentifiers: ["com.google.Chrome"],
                profile: profile,
                bypassed: isBypassed
            )
        case .controller(let type):
            if type == .spotify || (type == .nowPlaying && isSpotifyNowPlaying) {
                NodebayProcessAudioEqualizer.shared.apply(
                    bundleIdentifiers: ["com.spotify.client"],
                    profile: profile,
                    bypassed: isBypassed
                )
            } else if type == .quickTime {
                NodebayProcessAudioEqualizer.shared.apply(
                    bundleIdentifiers: [QuickTimeController.bundleIdentifier],
                    profile: profile,
                    bypassed: isBypassed
                )
            } else if type == .nowPlaying, isChromeNowPlaying {
                NodebayProcessAudioEqualizer.shared.apply(
                    bundleIdentifiers: ["com.google.Chrome"],
                    profile: profile,
                    bypassed: isBypassed
                )
            } else if type == .nowPlaying, isQuickTimeNowPlaying {
                NodebayProcessAudioEqualizer.shared.apply(
                    bundleIdentifiers: [QuickTimeController.bundleIdentifier],
                    profile: profile,
                    bypassed: isBypassed
                )
            } else {
                NodebayProcessAudioEqualizer.shared.stop()
            }
        }
    }

    private func applyToLocalPlayer() {
        NodebayLocalAudioController.shared.apply(profile: profile, bypassed: isBypassed)
    }

    private func persist() {
        defaults.set(preset.rawValue, forKey: "nodebay.equalizer.preset")
        defaults.set(customGains.map { NSNumber(value: $0) }, forKey: "nodebay.equalizer.customGains")
        defaults.set(isBypassed, forKey: "nodebay.equalizer.bypassed")
    }
}
