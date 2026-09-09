import Foundation

@main
struct NowPlayingStateHarness {
    static func main() async throws {
        let controller = AdapterStateHarness()
        func update(_ json: String) throws -> NowPlayingUpdate {
            try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
        }
        await controller.handleAdapterUpdate(try update("""
        {"diff":false,"payload":{"bundleIdentifier":"music","title":"Track A","artist":"Artist A","album":"Album A","duration":180,"elapsedTime":30,"artworkData":"AQID","playing":true}}
        """))
        precondition(controller.playbackState.title == "Track A")
        precondition(controller.playbackState.artwork == Data([1, 2, 3]))
        await controller.handleAdapterUpdate(try update("""
        {"diff":true,"payload":{"elapsedTime":40}}
        """))
        precondition(controller.playbackState.title == "Track A")
        precondition(controller.playbackState.artwork == Data([1, 2, 3]))
        precondition(controller.playbackState.currentTime == 40)
        print("PASS same-owner partial updates preserve track metadata and artwork")

        await controller.handleAdapterUpdate(try update("""
        {"diff":true,"payload":{"bundleIdentifier":"chrome","playing":true}}
        """))
        let changed = controller.playbackState
        precondition(changed.bundleIdentifier == "chrome")
        precondition(changed.title.isEmpty && changed.artist.isEmpty && changed.album.isEmpty)
        precondition(changed.duration == 0 && changed.currentTime == 0 && changed.artwork == nil)
        precondition(changed.effectiveAudioCaptureBundleIdentifiers == ["chrome"])
        print("PASS new owner cannot inherit another source's title, artwork or timeline")

        await controller.handleAdapterUpdate(try update("""
        {"diff":false,"payload":{"bundleIdentifier":"chat.player","processIdentifier":123,"playing":true}}
        """))
        precondition(controller.playbackState.title.isEmpty && controller.playbackState.hasMedia)
        await controller.handleAdapterUpdate(try update("""
        {"diff":false,"payload":{"bundleIdentifier":"chat.player","processIdentifier":123,"playing":false}}
        """))
        precondition(!controller.playbackState.isPlaying && controller.playbackState.hasMedia)
        await controller.handleAdapterUpdate(try update("""
        {"diff":false,"payload":{"bundleIdentifier":"chat.player","processIdentifier":124,"playing":false}}
        """))
        precondition(!controller.playbackState.hasMedia)
        print("PASS untitled playback survives pause while an unrelated idle client remains unavailable")

        await controller.handleAdapterUpdate(try update("""
        {"diff":false,"payload":{}}
        """))
        precondition(!controller.playbackState.hasMedia)
        precondition(controller.playbackState.bundleIdentifier.isEmpty)
        print("PASS empty snapshot clears all previous playback content")
    }
}
