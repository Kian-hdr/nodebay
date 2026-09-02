// Compiles the production service with an isolated process boundary for deterministic tests.
import Foundation

struct ProcessResult: Sendable { let exitCode: Int32; let standardError: String }
enum MediaDownloaderService {
    static var ffmpegCandidates: [URL] { [URL(fileURLWithPath: CommandLine.arguments[2])] }
}
struct XPCHelperClient: Sendable {
    static let shared = XPCHelperClient()
    func firstAvailableApprovedExecutable(engine: String, candidates: [URL]) async -> URL? {
        CommandLine.arguments[1] == "unavailable" ? nil : candidates.first
    }
}
enum SafeProcessRunner {
    static func runApproved(engine: String, executable: URL, arguments: [String], timeout: Duration, maximumLogBytes: Int) async throws -> ProcessResult {
        if CommandLine.arguments[1] == "failure" { return ProcessResult(exitCode: 1, standardError: "private sentinel") }
        if ["cancel-during", "busy"].contains(CommandLine.arguments[1]) { try await Task.sleep(for: .seconds(20)) }
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return ProcessResult(exitCode: process.terminationStatus, standardError: "")
        }.value
    }
}

@main struct VideoCompressionHarness {
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let input = URL(fileURLWithPath: CommandLine.arguments[3])
        let outputs = URL(fileURLWithPath: CommandLine.arguments[4])
        let work = URL(fileURLWithPath: CommandLine.arguments[5])
        if mode == "arguments" {
            print(String(data: try JSONEncoder().encode(VideoCompressionService.ffmpegArguments(input: input, output: outputs)), encoding: .utf8)!)
            return
        }
        let service = VideoCompressionService(outputRoot: outputs, temporaryRoot: work)
        let task = Task {
            if mode == "cancel-before" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await service.compressCopy(of: input)
        }
        if mode == "cancel-during" {
            try await Task.sleep(for: .milliseconds(700))
            task.cancel()
        }
        if mode == "busy" {
            try await Task.sleep(for: .milliseconds(700))
            do {
                _ = try await service.compressCopy(of: input)
                print("{\"error\":\"busy guard failed\"}")
            } catch {
                print(String(data: try JSONEncoder().encode(["error": error.localizedDescription]), encoding: .utf8)!)
            }
            task.cancel()
            _ = try? await task.value
            return
        }
        do {
            let result = try await task.value
            let report: [String: Any] = ["output": result.outputURL.path, "original": result.originalSize,
                                         "compressed": result.compressedSize, "smaller": result.isSmaller]
            print(String(data: try JSONSerialization.data(withJSONObject: report), encoding: .utf8)!)
        } catch {
            let report = ["error": error is CancellationError ? "cancelled" : error.localizedDescription]
            print(String(data: try JSONEncoder().encode(report), encoding: .utf8)!)
        }
    }
}
