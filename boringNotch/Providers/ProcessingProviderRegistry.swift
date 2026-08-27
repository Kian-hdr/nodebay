import AppKit
import Foundation

enum EngineAvailability: String, Codable, Sendable {
    case bundled = "Bundled"
    case installed = "Installed"
    case unavailable = "Unavailable"
    case error = "Error"
}

struct EngineDiagnostic: Sendable, Equatable {
    let availability: EngineAvailability
    let version: String
    let location: String
    let message: String

    static func unavailable(_ message: String) -> Self {
        .init(availability: .unavailable, version: "Not installed", location: "Not available", message: message)
    }
}

struct ProcessingProviderDescriptor: Identifiable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let purpose: String
    let provider: String
    let officialURL: URL
    let license: String
    let runsLocally: Bool
    let requiresNetwork: Bool
    let inputTypes: [String]
    let outputTypes: [String]
    let pinnedVersion: String?
    let configurable: Bool
}

protocol ProcessingProvider: Sendable {
    var descriptor: ProcessingProviderDescriptor { get }
    func diagnose() async -> EngineDiagnostic
}

struct AnyProcessingProvider: ProcessingProvider, Identifiable, Sendable {
    let descriptor: ProcessingProviderDescriptor
    private let diagnostic: @Sendable () async -> EngineDiagnostic

    init<P: ProcessingProvider>(_ provider: P) {
        descriptor = provider.descriptor
        diagnostic = { await provider.diagnose() }
    }

    var id: String { descriptor.id }

    func diagnose() async -> EngineDiagnostic {
        await diagnostic()
    }
}

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum SafeProcessError: LocalizedError {
    case executableMissing
    case timedOut
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing: "Executable not found."
        case .timedOut: "The process did not finish within the allowed time."
        case .launchFailed(let message): "The process could not start: \(message)"
        }
    }
}

enum SafeProcessRunner {
    static func runApproved(
        engine: String,
        executable: URL,
        arguments: [String],
        timeout: Duration = .seconds(15),
        maximumLogBytes: Int = 32_768,
        progress: (@Sendable (MediaDownloadProgress) -> Void)? = nil
    ) async throws -> ProcessResult {
        // The sandboxed app cannot reliably inspect Homebrew symlinks. The
        // unsandboxed XPC helper resolves and validates this exact allowlisted
        // path before launching it.
        return try await XPCHelperClient.shared.runApprovedProcess(
            engine: engine,
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            maximumLogBytes: maximumLogBytes,
            progress: progress
        )
    }

    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: Duration = .seconds(15),
        maximumLogBytes: Int = 32_768
    ) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SafeProcessError.executableMissing
        }

        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await runToCompletion(
                    executable: executable,
                    arguments: arguments,
                    environment: environment,
                    maximumLogBytes: maximumLogBytes
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SafeProcessError.timedOut
            }

            guard let result = try await group.next() else {
                throw SafeProcessError.launchFailed("No process result was produced.")
            }
            group.cancelAll()
            return result
        }
    }

    private static func runToCompletion(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        maximumLogBytes: Int
    ) async throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = BoundedProcessBuffer(maximumBytes: maximumLogBytes)
        let stderrBuffer = BoundedProcessBuffer(maximumBytes: maximumLogBytes)
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                    stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                    let output = stdoutBuffer.stringValue
                    let error = stderrBuffer.stringValue
                    continuation.resume(returning: ProcessResult(exitCode: finished.terminationStatus, standardOutput: output, standardError: error))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: SafeProcessError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

}

private final class BoundedProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = max(0, maximumBytes)
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty, maximumBytes > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = maximumBytes - data.count
        if remaining > 0 { data.append(newData.prefix(remaining)) }
    }

    var stringValue: String {
        lock.lock()
        defer { lock.unlock() }
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ExecutableProvider: ProcessingProvider {
    let descriptor: ProcessingProviderDescriptor
    let candidateURLs: [URL]
    let versionArguments: [String]
    let bundled: Bool
    let engineID: String

    func diagnose() async -> EngineDiagnostic {
        var lastFailure: EngineDiagnostic?
        for executable in candidateURLs {
            do {
                let result = try await SafeProcessRunner.runApproved(engine: engineID, executable: executable, arguments: versionArguments, timeout: .seconds(8))
                if result.exitCode == -1 {
                    continue
                }
                let firstLine = (result.standardOutput.isEmpty ? result.standardError : result.standardOutput)
                    .components(separatedBy: .newlines).first ?? "Unknown"
                guard result.exitCode == 0 else {
                    lastFailure = .init(availability: .error, version: "Unknown", location: executable.path, message: "Version check exited with status \(result.exitCode).")
                    continue
                }
                return .init(availability: bundled ? .bundled : .installed, version: firstLine, location: executable.path, message: "Runtime check passed.")
            } catch {
                lastFailure = .init(availability: .error, version: "Unknown", location: executable.path, message: error.localizedDescription)
            }
        }
        return lastFailure ?? .unavailable("Install or bundle this engine to enable its features.")
    }
}

struct ImageOptimProvider: ProcessingProvider {
    let descriptor = ProcessingProviderDescriptor(
        id: "imageoptim",
        name: "ImageOptim",
        systemImage: "photo.badge.arrow.down",
        purpose: "Compress image copies without changing source files.",
        provider: "ImageOptim",
        officialURL: URL(string: "https://imageoptim.com/mac")!,
        license: "GPL-2.0-or-later",
        runsLocally: true,
        requiresNetwork: false,
        inputTypes: ["JPEG", "PNG", "GIF"],
        outputTypes: ["Optimized copy"],
        pinnedVersion: nil,
        configurable: true
    )

    func diagnose() async -> EngineDiagnostic {
        let appURL = URL(fileURLWithPath: "/Applications/ImageOptim.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return .unavailable("Install the ImageOptim companion application to enable compression.")
        }
        let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        return .init(availability: .installed, version: version, location: appURL.path, message: "Companion application detected.")
    }
}

struct BrowserBridgeProvider: ProcessingProvider {
    let descriptor = ProcessingProviderDescriptor(
        id: "browser-bridge",
        name: "Browser Media Bridge",
        systemImage: "puzzlepiece.extension",
        purpose: "Expose explicitly approved browser media tabs through local native messaging.",
        provider: "Nodebay",
        officialURL: NodebayBrand.sourceURL,
        license: "GPL-3.0",
        runsLocally: true,
        requiresNetwork: false,
        inputTypes: ["YouTube tabs", "YouTube Music tabs"],
        outputTypes: ["Independent media sessions"],
        pinnedVersion: BrowserMediaBridge.bridgeVersion,
        configurable: true
    )

    func diagnose() async -> EngineDiagnostic {
        let bridge = await MainActor.run { BrowserMediaBridge.shared }
        await bridge.refreshInstallationStatus()
        let status = await MainActor.run {
            (
                installed: bridge.isNativeHostInstalled,
                connected: bridge.isConnected,
                extensionVersion: bridge.extensionVersion,
                sessions: bridge.sessions.count,
                location: bridge.extensionDirectoryURL?.path,
                error: bridge.lastError
            )
        }
        if status.connected {
            return .init(
                availability: .installed,
                version: status.extensionVersion ?? BrowserMediaBridge.bridgeVersion,
                location: status.location ?? "Bundled with Nodebay",
                message: "Connected locally with \(status.sessions) compatible browser tab(s)."
            )
        }
        if status.installed {
            return .init(
                availability: .installed,
                version: BrowserMediaBridge.bridgeVersion,
                location: status.location ?? "Bundled with Nodebay",
                message: "Native host installed. Load or enable the bundled Chrome extension to connect tabs."
            )
        }
        return .unavailable(status.error ?? "Install the optional native host and bundled Chrome extension to enable browser tabs.")
    }
}

@MainActor
final class ProcessingProviderRegistry: ObservableObject {
    static let shared = ProcessingProviderRegistry()

    let providers: [AnyProcessingProvider]
    @Published private(set) var diagnostics: [String: EngineDiagnostic] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?

    private init() {
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        let markItDown = resources.appending(path: "markitdown-runtime/markitdown-local")
        let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin")
        let intelHomebrew = URL(fileURLWithPath: "/usr/local/bin")

        providers = [
            AnyProcessingProvider(ExecutableProvider(
                descriptor: .init(
                    id: "markitdown", name: "Microsoft MarkItDown", systemImage: "doc.text.magnifyingglass",
                    purpose: "Convert supported local documents into separate Markdown files.", provider: "Microsoft",
                    officialURL: URL(string: "https://github.com/microsoft/markitdown")!, license: "MIT",
                    runsLocally: true, requiresNetwork: false,
                    inputTypes: ["PDF", "DOCX", "PPTX", "XLSX", "XLS", "HTML", "CSV", "JSON", "XML", "EPUB", "MSG", "ZIP", "TXT", "RST"],
                    outputTypes: ["Markdown (.md)"], pinnedVersion: "0.1.7", configurable: false
                ), candidateURLs: [markItDown], versionArguments: ["--nodebay-version"], bundled: true, engineID: "markitdown"
            )),
            AnyProcessingProvider(ExecutableProvider(
                descriptor: .init(
                    id: "yt-dlp", name: "yt-dlp", systemImage: "arrow.down.circle",
                    purpose: "Inspect and download user-authorized media URLs.", provider: "yt-dlp contributors",
                    officialURL: URL(string: "https://github.com/yt-dlp/yt-dlp")!, license: "Unlicense with GPLv3+ components depending on distribution",
                    runsLocally: true, requiresNetwork: true, inputTypes: ["HTTP and HTTPS media URLs", "Playlists"],
                    outputTypes: ["Original media", "MP4", "MP3"], pinnedVersion: MediaDownloaderService.pinnedTestedVersion, configurable: true
                ), candidateURLs: [resources.appending(path: "engines/yt-dlp"), homebrew.appending(path: "yt-dlp"), intelHomebrew.appending(path: "yt-dlp")], versionArguments: ["--version"], bundled: false, engineID: "yt-dlp"
            )),
            AnyProcessingProvider(ExecutableProvider(
                descriptor: .init(
                    id: "ffmpeg", name: "FFmpeg", systemImage: "film.stack",
                    purpose: "Merge, remux, and extract downloaded media.", provider: "FFmpeg project",
                    officialURL: URL(string: "https://ffmpeg.org")!, license: "Depends on exact build configuration",
                    runsLocally: true, requiresNetwork: false, inputTypes: ["Audio and video streams"],
                    outputTypes: ["MP4", "MP3", "Original containers"], pinnedVersion: nil, configurable: false
                ), candidateURLs: [resources.appending(path: "engines/ffmpeg"), homebrew.appending(path: "ffmpeg"), intelHomebrew.appending(path: "ffmpeg")], versionArguments: ["-version"], bundled: false, engineID: "ffmpeg"
            )),
            AnyProcessingProvider(ImageOptimProvider()),
            AnyProcessingProvider(BrowserBridgeProvider()),
        ]
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let providers = providers
        var results: [String: EngineDiagnostic] = [:]
        await withTaskGroup(of: (String, EngineDiagnostic).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.diagnose()) }
            }
            for await (id, diagnostic) in group {
                results[id] = diagnostic
            }
        }
        diagnostics = results
        lastRefresh = Date()
        isRefreshing = false
    }
}
