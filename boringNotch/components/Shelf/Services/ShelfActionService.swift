//
//  ShelfActionService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import AVFoundation
import Foundation
import ImageIO

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmarkData):
            Bookmark(data: bookmarkData).withAccess { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        case .stack:
            break
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmarkData) = item.kind else { return }
        Bookmark(data: bookmarkData).withAccess { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }
}

enum MarkItDownConversionError: LocalizedError {
    case unsupportedFormat(String)
    case helperMissing
    case persistentFileCreationFailed
    case helperFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            return "The .\(fileExtension) format is not supported by the local converter."
        case .helperMissing:
            return "The bundled local MarkItDown converter could not be found."
        case .persistentFileCreationFailed:
            return "Nodebay could not create a persistent Markdown copy."
        case .helperFailed(let message):
            return message.isEmpty ? "The local MarkItDown converter failed." : message
        case .outputMissing:
            return "The converter finished without creating a Markdown file."
        }
    }
}

/// Runs the bundled MarkItDown helper with local files only. Remote URLs, plugins,
/// cloud services, audio transcription, and network-backed OCR are intentionally excluded.
actor MarkItDownConversionService {
    static let shared = MarkItDownConversionService()

    private static let supportedExtensions: Set<String> = [
        "pdf", "docx", "pptx", "xlsx", "xls", "html", "htm",
        "csv", "json", "jsonl", "xml", "rss", "atom", "epub",
        "msg", "zip", "txt", "md", "markdown", "rst", "log"
    ]

    nonisolated static func supports(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func convert(_ inputURL: URL) async throws -> URL {
        let fileExtension = inputURL.pathExtension.lowercased()
        guard Self.supports(inputURL) else {
            throw MarkItDownConversionError.unsupportedFormat(fileExtension)
        }

        guard let runtimeURL = Bundle.main.url(forResource: "markitdown-runtime", withExtension: nil) else {
            throw MarkItDownConversionError.helperMissing
        }
        let helperURL = runtimeURL.appendingPathComponent("markitdown-local", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw MarkItDownConversionError.helperMissing
        }

        let outputURL: URL
        do {
            outputURL = try NodebayManagedFileStorage.uniqueOutputURL(
                for: .markdown,
                suggestedName: "\(inputURL.deletingPathExtension().lastPathComponent).md"
            )
        } catch {
            throw MarkItDownConversionError.persistentFileCreationFailed
        }

        let inputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markitdown-input-\(UUID().uuidString)", isDirectory: true)
        let localInputURL = inputDirectory.appendingPathComponent(inputURL.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try inputURL.accessSecurityScopedResource { accessibleURL in
                try FileManager.default.copyItem(at: accessibleURL, to: localInputURL)
            }

            try await runHelper(helperURL, input: localInputURL, output: outputURL)

            guard FileManager.default.fileExists(atPath: outputURL.path),
                  (try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                throw MarkItDownConversionError.outputMissing
            }

            try? FileManager.default.removeItem(at: inputDirectory)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: inputDirectory)
            NodebayManagedFileStorage.removeFailedOutput(at: outputURL)
            throw error
        }
    }

    private func runHelper(_ helperURL: URL, input: URL, output: URL) async throws {
        let result = try await SafeProcessRunner.runApproved(
            engine: "markitdown",
            executable: helperURL,
            arguments: ["--input", input.path, "--output", output.path],
            timeout: .seconds(180),
            maximumLogBytes: 16_384
        )
        guard result.exitCode == 0 else {
            throw MarkItDownConversionError.helperFailed(result.standardError)
        }
    }
}

enum VideoToGIFConversionError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableDuration
    case ffmpegUnavailable
    case persistentFileCreationFailed
    case conversionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension):
            return "The .\(fileExtension) format is not supported. Use an MP4, MOV, or M4V video."
        case .unreadableDuration:
            return "Nodebay could not read this video's duration."
        case .ffmpegUnavailable:
            return "FFmpeg is required to create GIFs. Install it with `brew install ffmpeg`, then try again."
        case .persistentFileCreationFailed:
            return "Nodebay could not create a persistent GIF copy."
        case .conversionFailed(let message):
            return message.isEmpty ? "FFmpeg could not create the GIF." : "FFmpeg could not create the GIF: \(message)"
        case .invalidOutput:
            return "The conversion finished without producing a readable animated GIF."
        }
    }
}

enum VideoToGIFConversionResult: Sendable {
    case gif(outputURL: URL, duration: Double, frameCount: Int)
    case keptOriginalVideo(videoURL: URL, duration: Double, maximumDuration: Double)
}

/// Creates a presentation-friendly GIF only when the complete source video fits
/// within Nodebay's bounded animation budget. Longer sources remain videos.
actor VideoToGIFConversionService {
    static let shared = VideoToGIFConversionService()

    nonisolated static let framesPerSecond = 12
    nonisolated static let maximumFrameCount = 180
    nonisolated static let maximumDuration = Double(maximumFrameCount) / Double(framesPerSecond)

    private static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    nonisolated static func supports(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func convertIfEligible(_ inputURL: URL) async throws -> VideoToGIFConversionResult {
        guard Self.supports(inputURL) else {
            throw VideoToGIFConversionError.unsupportedFormat(inputURL.pathExtension.lowercased())
        }

        let duration = try await inputURL.accessSecurityScopedResource { accessibleURL in
            let time = try await AVURLAsset(url: accessibleURL).load(.duration)
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite, seconds > 0 else {
                throw VideoToGIFConversionError.unreadableDuration
            }
            return seconds
        }

        guard duration <= Self.maximumDuration + 0.001 else {
            return .keptOriginalVideo(
                videoURL: inputURL,
                duration: duration,
                maximumDuration: Self.maximumDuration
            )
        }

        guard let ffmpeg = await XPCHelperClient.shared.firstAvailableApprovedExecutable(
            engine: "ffmpeg",
            candidates: MediaDownloaderService.ffmpegCandidates
        ) else {
            throw VideoToGIFConversionError.ffmpegUnavailable
        }

        let outputURL: URL
        do {
            outputURL = try NodebayManagedFileStorage.uniqueOutputURL(
                for: .media,
                suggestedName: "\(inputURL.deletingPathExtension().lastPathComponent).gif"
            )
        } catch {
            throw VideoToGIFConversionError.persistentFileCreationFailed
        }

        let inputDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("video-to-gif-input-\(UUID().uuidString)", isDirectory: true)
        let localInputURL = inputDirectory.appendingPathComponent(inputURL.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
            try inputURL.accessSecurityScopedResource { accessibleURL in
                try FileManager.default.copyItem(at: accessibleURL, to: localInputURL)
            }

            let result = try await SafeProcessRunner.runApproved(
                engine: "ffmpeg",
                executable: ffmpeg,
                arguments: Self.ffmpegArguments(input: localInputURL, output: outputURL),
                timeout: .seconds(120),
                maximumLogBytes: 32_768
            )
            guard result.exitCode == 0 else {
                throw VideoToGIFConversionError.conversionFailed(Self.boundedDiagnostic(result.standardError))
            }

            let frameCount = try Self.validatedFrameCount(at: outputURL)
            try? FileManager.default.removeItem(at: inputDirectory)
            return .gif(outputURL: outputURL, duration: duration, frameCount: frameCount)
        } catch {
            try? FileManager.default.removeItem(at: inputDirectory)
            NodebayManagedFileStorage.removeFailedOutput(at: outputURL, category: .media)
            throw error
        }
    }

    nonisolated static func ffmpegArguments(input: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-loglevel", "error", "-n",
            "-i", input.path,
            "-filter_complex",
            "[0:v]fps=\(framesPerSecond),scale=960:540:force_original_aspect_ratio=decrease:force_divisible_by=2,split[frames][palette_source];[palette_source]palettegen=max_colors=256:stats_mode=diff[palette];[frames][palette]paletteuse=dither=sierra2_4a:diff_mode=rectangle",
            "-an", "-loop", "0", output.path
        ]
    }

    private nonisolated static func validatedFrameCount(at outputURL: URL) throws -> Int {
        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              CGImageSourceGetType(source) as String? == "com.compuserve.gif" else {
            throw VideoToGIFConversionError.invalidOutput
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1, frameCount <= maximumFrameCount else {
            throw VideoToGIFConversionError.invalidOutput
        }
        return frameCount
    }

    private nonisolated static func boundedDiagnostic(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
    }
}
