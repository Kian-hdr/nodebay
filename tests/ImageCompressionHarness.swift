// Compiles the production image service with an isolated optimizer boundary.
// ImageOptim's installed-app check remains real, but the app is never launched.
import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardError: String
}

actor ImageOptimizerProbe {
    static let shared = ImageOptimizerProbe()
    private(set) var arguments: [String] = []
    private(set) var copiedSize = 0

    func record(arguments: [String], copiedSize: Int) {
        self.arguments = arguments
        self.copiedSize = copiedSize
    }
}

enum SafeProcessRunner {
    static func runApproved(
        engine: String,
        executable: URL,
        arguments: [String],
        timeout: Duration,
        maximumLogBytes: Int
    ) async throws -> ProcessResult {
        guard engine == "imageoptim", arguments.count == 1 else {
            throw NSError(domain: "ImageCompressionHarness", code: 1)
        }
        let output = URL(fileURLWithPath: arguments[0])
        let copiedBytes = try Data(contentsOf: output)
        await ImageOptimizerProbe.shared.record(arguments: arguments, copiedSize: copiedBytes.count)
        switch CommandLine.arguments[1] {
        case "failure":
            return ProcessResult(exitCode: 1, standardError: "fixture optimizer failure")
        case "throws":
            throw NSError(domain: "ImageCompressionHarness", code: 2)
        case "invalid":
            try Data("not an image".utf8).write(to: output)
        case "cancel-during":
            try await Task.sleep(for: .seconds(30))
        default:
            let optimizedFixture = URL(fileURLWithPath: CommandLine.arguments[5])
            try Data(contentsOf: optimizedFixture).write(to: output)
        }
        return ProcessResult(exitCode: 0, standardError: "")
    }
}

@main struct ImageCompressionHarness {
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let input = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputRoot = URL(fileURLWithPath: CommandLine.arguments[3])
        let suffix = CommandLine.arguments[4]
        let service = ImageOptimCompressionService(outputRoot: outputRoot)
        let task = Task {
            if mode == "cancel-before" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await service.compressCopy(of: input, suffix: suffix)
        }
        if mode == "cancel-during" {
            // Wait for the stub optimizer to own the copy before cancelling.
            for _ in 0..<500 {
                if !(await ImageOptimizerProbe.shared.arguments).isEmpty { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            task.cancel()
        }

        var report: [String: Any]
        do {
            let result = try await task.value
            report = [
                "source": result.sourceURL.path,
                "output": result.outputURL.path,
                "original": result.originalSize,
                "compressed": result.compressedSize,
                "saved": result.bytesSaved,
                "percentage": result.percentageSaved,
                "smaller": result.isSmaller,
            ]
        } catch {
            report = ["error": error is CancellationError ? "cancelled" : error.localizedDescription]
        }
        report["optimizerArguments"] = await ImageOptimizerProbe.shared.arguments
        report["copiedSize"] = await ImageOptimizerProbe.shared.copiedSize
        print(String(data: try JSONSerialization.data(withJSONObject: report), encoding: .utf8)!)
    }
}
