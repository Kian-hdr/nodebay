import AVFoundation
import Foundation

struct VideoCompressionResult: Sendable {
    let outputURL: URL
    let originalSize: Int64
    let compressedSize: Int64
    var isSmaller: Bool { compressedSize < originalSize }
    var bytesSaved: Int64 { max(0, originalSize - compressedSize) }
    var percentageSaved: Double { originalSize > 0 ? Double(bytesSaved) / Double(originalSize) * 100 : 0 }
}

enum VideoCompressionError: LocalizedError {
    case unsupported, unavailable, busy, invalidVideo, hdrUnsupported, encodingFailed, invalidOutput

    var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a local MP4 video to compress."
        case .unavailable: "FFmpeg is required. Install it with brew install ffmpeg, then try again."
        case .busy: "Another video is being compressed. Wait for it to finish or cancel it first."
        case .invalidVideo: "This MP4 does not contain a readable video with a valid duration."
        case .hdrUnsupported: "HDR video compression is not supported yet. Keep the original to preserve its colors."
        case .encodingFailed: "FFmpeg could not compress this video. Check that the file is readable and your FFmpeg installation includes libx264."
        case .invalidOutput: "Compression did not produce a complete, playable video. The original was not changed."
        }
    }
}

/// One local encode at a time. Only a staged copy is passed to the helper;
/// completed results live in Application Support, not purgeable temporary storage.
actor VideoCompressionService {
    static let shared = VideoCompressionService()
    private var isRunning = false
    private let outputRoot: URL
    private let temporaryRoot: URL

    init(outputRoot: URL? = nil, temporaryRoot: URL = FileManager.default.temporaryDirectory) {
        self.outputRoot = outputRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodebay/Generated Videos", isDirectory: true)
        self.temporaryRoot = temporaryRoot
    }

    nonisolated static func supports(_ url: URL) -> Bool {
        url.isFileURL && url.pathExtension.lowercased() == "mp4"
    }

    func compressCopy(of sourceURL: URL) async throws -> VideoCompressionResult {
        guard Self.supports(sourceURL) else { throw VideoCompressionError.unsupported }
        guard !isRunning else { throw VideoCompressionError.busy }
        isRunning = true
        defer { isRunning = false }
        try Task.checkCancellation()
        guard let ffmpeg = await XPCHelperClient.shared.firstAvailableApprovedExecutable(
            engine: "ffmpeg", candidates: MediaDownloaderService.ffmpegCandidates
        ) else { throw VideoCompressionError.unavailable }

        let jobID = UUID().uuidString
        let staging = temporaryRoot.appendingPathComponent("nodebay-video-\(jobID)", isDirectory: true)
        let stagedInput = staging.appendingPathComponent("input.mp4")
        let stagedOutput = staging.appendingPathComponent("compressed.mp4")
        let resultDirectory = outputRoot.appendingPathComponent(jobID, isDirectory: true)
        let output = resultDirectory.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "-compressed.mp4")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var retained = false
        defer {
            try? FileManager.default.removeItem(at: staging)
            if !retained { try? FileManager.default.removeItem(at: resultDirectory) }
        }

        // Hold the drag/bookmark grant until the source has been copied, including on external disks.
        try sourceURL.accessSecurityScopedResource { accessibleURL in
            try FileManager.default.copyItem(at: accessibleURL, to: stagedInput)
        }
        try Task.checkCancellation()
        let originalSize = Int64(try stagedInput.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let source = AVURLAsset(url: stagedInput)
        let duration = try await source.load(.duration).seconds
        let sourceVideo = try await source.loadTracks(withMediaType: .video)
        let sourceAudio = try await source.loadTracks(withMediaType: .audio)
        guard originalSize > 0, duration.isFinite, duration > 0, !sourceVideo.isEmpty else {
            throw VideoCompressionError.invalidVideo
        }
        // This first preset is SDR. Reject HDR rather than silently flattening its colors.
        for description in try await sourceVideo[0].load(.formatDescriptions) {
            guard let extensions = CMFormatDescriptionGetExtensions(description) else { continue }
            let transfer = (extensions as NSDictionary)[kCMFormatDescriptionExtension_TransferFunction] as? String
            if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                || transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String {
                throw VideoCompressionError.hdrUnsupported
            }
        }

        let result = try await SafeProcessRunner.runApproved(
            engine: "ffmpeg", executable: ffmpeg,
            arguments: Self.ffmpegArguments(input: stagedInput, output: stagedOutput),
            timeout: .seconds(3_600), maximumLogBytes: 8_192
        )
        try Task.checkCancellation()
        // Do not surface FFmpeg stderr: malformed metadata can contain private document text or paths.
        guard result.exitCode == 0 else { throw VideoCompressionError.encodingFailed }
        let asset = AVURLAsset(url: stagedOutput)
        let outputDuration = try await asset.load(.duration).seconds
        let playable = try await asset.load(.isPlayable)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let compressedSize = Int64(try stagedOutput.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard playable, !video.isEmpty, sourceAudio.isEmpty || !audio.isEmpty,
              compressedSize > 0, outputDuration.isFinite,
              abs(outputDuration - duration) <= max(1, duration * 0.01) else {
            throw VideoCompressionError.invalidOutput
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)
        // A UUID directory and non-overwriting copy avoid both naming collisions and replacement races.
        try FileManager.default.copyItem(at: stagedOutput, to: output)
        try Task.checkCancellation()
        retained = true
        return VideoCompressionResult(outputURL: output, originalSize: originalSize, compressedSize: compressedSize)
    }

    nonisolated static func ffmpegArguments(input: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-protocol_whitelist", "file", "-f", "mov", "-threads", "2", "-i", input.path,
            "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "-1", "-map_chapters", "-1",
            "-vf", "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
            "-c:v", "libx264", "-preset", "medium", "-crf", "26", "-pix_fmt", "yuv420p",
            "-threads", "2", "-filter_threads", "1", "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart", "-f", "mp4", output.path
        ]
    }
}
