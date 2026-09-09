import AppKit
import Foundation
import ImageIO

struct ImageCompressionResult: Sendable {
    let sourceURL: URL
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    let metadataStatus: String
    let compressionMode: String

    var bytesSaved: Int64 { max(0, originalSize - compressedSize) }
    var percentageSaved: Double {
        guard originalSize > 0 else { return 0 }
        return Double(bytesSaved) / Double(originalSize) * 100
    }
    var isSmaller: Bool { compressedSize < originalSize }
}

enum ImageOptimCompressionError: LocalizedError {
    case unavailable
    case unsupportedFormat
    case sourceUnavailable
    case copyFailed(String)
    case optimizationFailed(String)
    case invalidResult

    var errorDescription: String? {
        switch self {
        case .unavailable: "ImageOptim is not installed in /Applications."
        case .unsupportedFormat: "This image format is not supported by the ImageOptim integration."
        case .sourceUnavailable: "The source image is no longer available."
        case .copyFailed(let message): "Nodebay could not create a safe image copy: \(message)"
        case .optimizationFailed(let message): "ImageOptim could not compress the copy: \(message)"
        case .invalidResult: "ImageOptim finished, but the resulting copy is not a valid image."
        }
    }
}

actor ImageOptimCompressionService {
    static let shared = ImageOptimCompressionService()
    private let outputRoot: URL

    init(outputRoot: URL? = nil) {
        self.outputRoot = outputRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodebay/Generated Images", isDirectory: true)
    }

    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]
    static let appURL = URL(fileURLWithPath: "/Applications/ImageOptim.app")
    static let executableURL = appURL.appending(path: "Contents/MacOS/ImageOptim")

    nonisolated static func supports(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    func compressCopy(of sourceURL: URL, suffix: String = "optimized") async throws -> ImageCompressionResult {
        try Task.checkCancellation()
        guard Self.isInstalled else { throw ImageOptimCompressionError.unavailable }
        guard Self.supports(sourceURL) else { throw ImageOptimCompressionError.unsupportedFormat }
        let outputURL = collisionSafeURL(for: sourceURL, suffix: suffix)
        var createdCopy = false
        var retained = false
        defer {
            if createdCopy && !retained { try? FileManager.default.removeItem(at: outputURL) }
        }

        do {
            // A file grant does not grant write access to its parent directory.
            // Keep every source read inside the grant and create the result in our container.
            try sourceURL.accessSecurityScopedResource { accessibleURL in
                guard FileManager.default.fileExists(atPath: accessibleURL.path) else {
                    throw ImageOptimCompressionError.sourceUnavailable
                }
                try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: accessibleURL.resolvingSymlinksInPath(), to: outputURL)
                createdCopy = true
            }
            // A read-only original can still produce a writable, independent copy.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        } catch let error as ImageOptimCompressionError {
            throw error
        } catch {
            throw ImageOptimCompressionError.copyFailed(error.localizedDescription)
        }

        let originalSize = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        try Task.checkCancellation()
        let result = try await SafeProcessRunner.runApproved(
            engine: "imageoptim",
            executable: Self.executableURL,
            arguments: [outputURL.path],
            timeout: .seconds(600),
            maximumLogBytes: 16_384
        )
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ImageOptimCompressionError.optimizationFailed(result.standardError)
        }
        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageOptimCompressionError.invalidResult
        }
        // ImageOptim changes the file in another process; bypass URL's cached resource values.
        let compressedSize = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        retained = true
        return ImageCompressionResult(
            sourceURL: sourceURL,
            outputURL: outputURL,
            originalSize: originalSize,
            compressedSize: compressedSize,
            metadataStatus: "Controlled by ImageOptim preferences",
            compressionMode: "Controlled by ImageOptim preferences"
        )
    }

    private func collisionSafeURL(for source: URL, suffix: String) -> URL {
        let directory = outputRoot
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let safeSuffix = suffix
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeSuffix.isEmpty ? "\(stem)-optimized" : "\(stem)-\(safeSuffix)"

        var candidate = directory.appending(path: base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)-\(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
