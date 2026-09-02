import Foundation

struct ProcessResult: Sendable { let exitCode: Int32; let standardOutput, standardError: String }
final class XPCHelperClient: @unchecked Sendable {
    static let shared = XPCHelperClient()
    func firstAvailableApprovedExecutable(engine: String, candidates: [URL]) async -> URL? {
        CommandLine.arguments[1] == "missing" ? nil : candidates.first
    }
}
enum SafeProcessRunner {
    static func runApproved(engine: String, executable: URL, arguments: [String], timeout: Duration, maximumLogBytes: Int = 32_768) async throws -> ProcessResult {
        switch CommandLine.arguments[1] {
        case "crash": return .init(exitCode: 137, standardOutput: "private data", standardError: "private paths")
        case "timeout": throw NSError(domain: "private timeout", code: 1)
        case "cancel": try await Task.sleep(for: .seconds(10))
        default: break
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1) (allow default) (deny network*)", executable.path,
            "--background", "--factory-startup", "--disable-autoexec", "--offline-mode", "--threads", "2", "--python-exit-code", "7",
            "--python", CommandLine.arguments[4], "--", "--mode", arguments[0], "--job", arguments[1]]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        return .init(exitCode: process.terminationStatus, standardOutput: "", standardError: "")
    }
}

#if !STL_COORDINATOR_TEST
@main enum Harness {
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let service = STLRepairService(root: URL(fileURLWithPath: CommandLine.arguments[3]))
        let job = Task { try await service.process(URL(fileURLWithPath: CommandLine.arguments[2]), mode: mode == "inspect" ? .inspect : mode == "thorough-unconfirmed" ? .thorough : .safe) }
        if mode == "cancel" { try await Task.sleep(for: .milliseconds(50)); job.cancel() }
        var output: [String: Any]
        do {
            let result = try await job.value
            output = ["output": result.outputURL?.path ?? "", "status": result.report.status]
        } catch { output = ["error": error is CancellationError ? "Cancelled" : (error as? STLRepairError)?.rawValue ?? "Redacted"] }
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
    }
}
#endif
