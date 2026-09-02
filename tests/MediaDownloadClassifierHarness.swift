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
        expect(metadata("https://youtube.com/shorts/visual"), .video, .safeFallback)
        expect(metadata("https://youtube.com/watch?v=mixed", categories: ["Music"], artist: "A"), .video, .safeFallback)
        expect(metadata("https://youtube.com/watch?v=empty", track: " ", artist: "\n"), .video, .safeFallback)
        expect(metadata("https://music.youtube.com.example.test/watch?v=spoof"), .video, .safeFallback)
        expect(metadata("https://example.test/audio", videoCodec: "none", audioCodec: ""), .video, .safeFallback)
        expect(metadata("https://example.test/audio", videoCodec: "none", audioCodec: "opus"), .audio, .high)
        let selectedAudioWithVideo: [String: Any] = [
            "title": "Official song music audio only", "vcodec": "none", "acodec": "opus",
            "formats": [["vcodec": "avc1", "acodec": "none"], ["vcodec": "none", "acodec": "opus"]],
        ]
        expect(.from(selectedAudioWithVideo, url: URL(string: "https://youtu.be/video")!), .video, .safeFallback)
        let official: [String: Any] = ["track": "Private track", "artists": ["Private artist"]]
        let classified = MediaDownloadClassifier.classify(.from(official, url: URL(string: "https://youtube.com/watch?v=private")!))
        precondition(classified.kind == .audio && classified.confidence == .high)
        precondition(!classified.reason.contains("Private") && !classified.reason.contains("http"))
        let encoded = try! JSONEncoder().encode(classified)
        precondition(try! JSONDecoder().decode(MediaDownloadClassification.self, from: encoded) == classified)
        // Each flat playlist entry is classified independently, not by the parent title/category.
        let playlist = [metadata("https://music.youtube.com/watch?v=track"), metadata("https://youtube.com/shorts/visual")]
        precondition(playlist.map { MediaDownloadClassifier.classify($0).kind } == [.audio, .video])
        print("Media download classifier fixtures passed")
    }
}
