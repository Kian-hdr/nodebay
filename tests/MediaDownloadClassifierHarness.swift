import Foundation

private func metadata(
    _ url: String,
    categories: [String] = [],
    track: String? = nil,
    artist: String? = nil,
    mediaType: String? = nil,
    videoCodec: String? = nil,
    audioCodec: String? = nil
) -> MediaClassificationMetadata {
    MediaClassificationMetadata(
        url: URL(string: url)!,
        categories: categories,
        track: track,
        artist: artist,
        mediaType: mediaType,
        videoCodec: videoCodec,
        audioCodec: audioCodec
    )
}

private func expect(
    _ metadata: MediaClassificationMetadata,
    _ kind: MediaDownloadKind,
    _ confidence: MediaClassificationConfidence
) {
    let result = MediaDownloadClassifier.classify(metadata)
    precondition(result.kind == kind, "Unexpected kind: \(result)")
    precondition(result.confidence == confidence, "Unexpected confidence: \(result)")
    precondition(!result.reason.isEmpty)
}

@main
struct MediaDownloadClassifierHarness {
    static func main() {
        expect(metadata("https://music.youtube.com/watch?v=track"), .audio, .high)
        expect(metadata("https://youtu.be/video"), .video, .safeFallback)
        expect(metadata("https://www.youtube.com/watch?v=video"), .video, .safeFallback)
        expect(
            metadata(
                "https://www.youtube.com/watch?v=official",
                categories: ["Music"],
                track: "Song",
                artist: "Artist"
            ),
            .audio,
            .high
        )
        expect(
            metadata("https://www.youtube.com/watch?v=mixed", categories: ["Music"]),
            .video,
            .safeFallback
        )
        expect(
            metadata("https://example.test/audio", mediaType: "audio", videoCodec: "none", audioCodec: "aac"),
            .audio,
            .high
        )
        expect(metadata("https://example.test/unknown"), .video, .safeFallback)
        print("Media download classifier fixtures passed")
    }
}
