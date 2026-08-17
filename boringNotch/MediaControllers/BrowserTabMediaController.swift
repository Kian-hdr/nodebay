import Combine
import Foundation

final class BrowserTabMediaController: MediaControllerProtocol {
    let sessionID: String
    private let stateSubject: CurrentValueSubject<PlaybackState, Never>
    private(set) var session: BrowserMediaSession
    private var available = true

    init(session: BrowserMediaSession) {
        self.sessionID = session.id
        self.session = session
        self.stateSubject = CurrentValueSubject(session.playbackState)
    }

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { true }
    var supportsFavorite: Bool { false }

    func update(session: BrowserMediaSession) {
        self.session = session
        available = true
        stateSubject.send(session.playbackState)
    }

    func markUnavailable() {
        available = false
    }

    func setFavorite(_ favorite: Bool) async {}
    func play() async { await command("play") }
    func pause() async { await command("pause") }
    func seek(to time: Double) async { await command("seek", value: time) }
    func nextTrack() async { await command("next") }
    func previousTrack() async { await command("previous") }
    func togglePlay() async { await command("togglePlay") }
    func toggleShuffle() async {}
    func toggleRepeat() async {}
    func setVolume(_ level: Double) async { await command("setVolume", value: level) }
    func isActive() -> Bool { available }
    func updatePlaybackInfo() async {}

    private func command(_ action: String, value: Double? = nil) async {
        let targetSessionID = sessionID
        _ = await MainActor.run {
            BrowserMediaBridge.shared.sendCommand(sessionID: targetSessionID, action: action, value: value)
        }
    }
}
