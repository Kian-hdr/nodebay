//
//  MediaControllerProtocol.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    var playbackIssue: String? { get }
    
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
}

extension MediaControllerProtocol {
    var playbackIssue: String? { nil }
}

enum MediaPlaybackIssue {
    static func message(for error: Error, applicationName: String) -> String {
        let error = error as NSError
        if error.domain == AppleScriptHelper.errorDomain && [-1743, -1744].contains(error.code) {
            return "Allow Nodebay to control \(applicationName) in System Settings > Privacy & Security > Automation, then refresh media sources."
        }
        return "Nodebay could not read \(applicationName)'s playback. Try refreshing media sources."
    }
}
