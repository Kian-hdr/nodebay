import AppKit
import Foundation
import Network

struct BrowserMediaSession: Identifiable, Hashable {
    let id: String
    let tabID: Int
    let browserName: String
    let siteName: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let playbackRate: Double
    let volume: Double
    let isMuted: Bool
    let canSeek: Bool
    let canGoNext: Bool
    let canGoPrevious: Bool
    let lastUpdated: Date

    var displayName: String {
        title.isEmpty ? "\(siteName) tab \(tabID)" : "\(siteName): \(title)"
    }

    var playbackState: PlaybackState {
        PlaybackState(
            bundleIdentifier: "com.google.Chrome",
            audioCaptureBundleIdentifiers: ["com.google.Chrome"],
            isPlaying: isPlaying,
            title: title.isEmpty ? siteName : title,
            artist: artist.isEmpty ? browserName : artist,
            album: siteName,
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            lastUpdated: lastUpdated,
            volume: isMuted ? 0 : volume
        )
    }
}

@MainActor
final class BrowserMediaBridge: ObservableObject {
    static let shared = BrowserMediaBridge()
    nonisolated static let nativeHostName = "com.nodebay.browser_bridge"
    nonisolated static let extensionID = "moppfhahpgimiknnknkmchmjljfhhdaf"
    nonisolated static let bridgeVersion = "0.1.0"
    private static let port: NWEndpoint.Port = 47_321
    private static let maximumBufferedBytes = 1_048_576

    @Published private(set) var sessions: [BrowserMediaSession] = []
    @Published private(set) var isConnected = false
    @Published private(set) var isNativeHostInstalled = false
    @Published private(set) var extensionVersion: String?
    @Published private(set) var lastError: String?

    private var sessionsByID: [String: BrowserMediaSession] = [:]
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var pruneTimer: Timer?
    private let networkQueue = DispatchQueue(label: "Nodebay.BrowserMediaBridge")

    private init() {
        startListener()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStaleSessions() }
        }
        Task { await refreshInstallationStatus() }
    }

    deinit {
        pruneTimer?.invalidate()
        connection?.cancel()
        listener?.cancel()
    }

    var extensionDirectoryURL: URL? {
        Bundle.main.resourceURL?.appending(path: "BrowserBridge/extension", directoryHint: .isDirectory)
    }

    var nativeHostExecutableURL: URL? {
        Bundle.main.resourceURL?.appending(path: "BrowserBridge/native/nodebay-browser-bridge")
    }

    func installNativeHost() async {
        guard let executable = nativeHostExecutableURL else {
            lastError = "The bundled native host could not be found."
            return
        }
        let result = await XPCHelperClient.shared.installBrowserBridgeManifest(
            nativeHostPath: executable.path,
            extensionID: Self.extensionID
        )
        isNativeHostInstalled = result.success
        lastError = result.success ? nil : (result.message ?? "Native host installation failed.")
    }

    func removeNativeHost() async {
        let result = await XPCHelperClient.shared.removeBrowserBridgeManifest()
        isNativeHostInstalled = !result.success
        lastError = result.success ? nil : (result.message ?? "Native host removal failed.")
    }

    func refreshInstallationStatus() async {
        let result = await XPCHelperClient.shared.browserBridgeManifestStatus()
        isNativeHostInstalled = result.installed
        if let message = result.message, !message.isEmpty, !result.installed {
            lastError = message
        }
    }

    func revealExtension() {
        guard let extensionDirectoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([extensionDirectoryURL])
    }

    func openChromeExtensions() {
        guard let url = URL(string: "chrome://extensions") else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func sendCommand(sessionID: String, action: String, value: Double? = nil) -> Bool {
        guard let connection, let session = sessionsByID[sessionID] else {
            lastError = "That browser tab is no longer connected."
            return false
        }
        var object: [String: Any] = [
            "type": "command",
            "tabId": session.tabID,
            "action": action,
        ]
        if let value { object["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var line = data
        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { [weak self] error in
            if let error {
                Task { @MainActor in self?.lastError = "Browser command failed: \(error.localizedDescription)" }
            }
        })
        return true
    }

    private func startListener() {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: Self.port)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.lastError = nil
                    case .failed(let error):
                        self?.lastError = "Local browser bridge failed: \(error.localizedDescription)"
                        self?.isConnected = false
                    case .cancelled:
                        self?.isConnected = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: networkQueue)
        } catch {
            lastError = "Could not start the local browser bridge: \(error.localizedDescription)"
        }
    }

    private func accept(_ newConnection: NWConnection) {
        let endpoint = String(describing: newConnection.endpoint)
        guard endpoint.hasPrefix("127.0.0.1:") || endpoint.hasPrefix("[::1]:") else {
            newConnection.cancel()
            return
        }

        connection?.cancel()
        connection = newConnection
        receiveBuffer.removeAll(keepingCapacity: true)
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            Task { @MainActor in
                guard let self, self.connection === newConnection else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.lastError = nil
                case .failed(let error):
                    self.disconnect(message: "Browser bridge disconnected: \(error.localizedDescription)")
                case .cancelled:
                    self.disconnect(message: nil)
                default:
                    break
                }
            }
        }
        newConnection.start(queue: networkQueue)
        receiveNext(on: newConnection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, complete, error in
            Task { @MainActor in
                guard let self, let connection, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffer.append(data)
                    if self.receiveBuffer.count > Self.maximumBufferedBytes {
                        self.disconnect(message: "Browser bridge message exceeded the local size limit.")
                        return
                    }
                    self.consumeLines()
                }
                if let error {
                    self.disconnect(message: "Browser bridge read failed: \(error.localizedDescription)")
                } else if complete {
                    self.disconnect(message: nil)
                } else {
                    self.receiveNext(on: connection)
                }
            }
        }
    }

    private func consumeLines() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleMessage(Data(line))
        }
    }

    private func handleMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(IncomingMessage.self, from: data) else {
            lastError = "The browser bridge sent an invalid local message."
            return
        }
        switch message.type {
        case "hello", "nativeHostConnected":
            extensionVersion = message.extensionVersion ?? extensionVersion
            isConnected = true
        case "tabState":
            guard let wire = message.session else { return }
            let id = "chrome:\(wire.tabID)"
            sessionsByID[id] = BrowserMediaSession(
                id: id,
                tabID: wire.tabID,
                browserName: "Google Chrome",
                siteName: wire.siteName,
                title: wire.title,
                artist: wire.artist,
                isPlaying: wire.isPlaying,
                currentTime: wire.currentTime,
                duration: wire.duration,
                playbackRate: wire.playbackRate,
                volume: wire.volume,
                isMuted: wire.isMuted,
                canSeek: wire.canSeek,
                canGoNext: wire.canGoNext,
                canGoPrevious: wire.canGoPrevious,
                lastUpdated: Date()
            )
            publishSessions()
        case "tabRemoved":
            guard let id = message.id else { return }
            sessionsByID.removeValue(forKey: id)
            publishSessions()
        case "error":
            lastError = message.message ?? "The browser bridge reported an error."
        default:
            break
        }
    }

    private func publishSessions() {
        sessions = sessionsByID.values.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying && !$1.isPlaying }
            if $0.siteName != $1.siteName { return $0.siteName.localizedCaseInsensitiveCompare($1.siteName) == .orderedAscending }
            if $0.title != $1.title { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return $0.tabID < $1.tabID
        }
    }

    private func pruneStaleSessions() {
        let cutoff = Date().addingTimeInterval(-12)
        let stale = sessionsByID.filter { $0.value.lastUpdated < cutoff }.map(\.key)
        guard !stale.isEmpty else { return }
        stale.forEach { sessionsByID.removeValue(forKey: $0) }
        publishSessions()
    }

    private func disconnect(message: String?) {
        connection?.cancel()
        connection = nil
        isConnected = false
        extensionVersion = nil
        sessionsByID.removeAll()
        publishSessions()
        if let message { lastError = message }
    }
}

private struct IncomingMessage: Decodable {
    let type: String
    let session: WireBrowserMediaSession?
    let id: String?
    let extensionVersion: String?
    let message: String?
}

private struct WireBrowserMediaSession: Decodable {
    let tabID: Int
    let siteName: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let playbackRate: Double
    let volume: Double
    let isMuted: Bool
    let canSeek: Bool
    let canGoNext: Bool
    let canGoPrevious: Bool
}
