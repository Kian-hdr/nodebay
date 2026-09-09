import Foundation

@main
struct NodebayEqualizerHarness {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        require(NodebayEqualizerProfile.frequencies == [60, 250, 1_000, 4_000, 12_000], "band centers")
        require(NodebayEqualizerProfile.preset(.flat, custom: []).gains == [0, 0, 0, 0, 0], "flat preset")
        require(NodebayEqualizerProfile.preset(.bassBoost, custom: []).gains == [6, 4, 1, -1, -2], "bass preset")
        require(NodebayEqualizerProfile.preset(.vocal, custom: []).gains == [-2, 0, 4, 3, 0], "vocal preset")
        require(NodebayEqualizerProfile.preset(.electronic, custom: []).gains == [4, 2, -1, 2, 4], "electronic preset")

        let clamped = NodebayEqualizerProfile(gains: [20, -20, 2])
        require(clamped.gains == [6, -12, 2, 0, 0], "gain clamp and missing bands")
        require(clamped.headroom == -6, "automatic headroom")
        require(NodebayEqualizerProfile(gains: [-4, -2, -1, -3, -8]).headroom == 0, "no unnecessary attenuation")
        require(NodebayEqualizerCurveScale.normalizedY(for: 6) == 0, "maximum boost maps to top")
        require(NodebayEqualizerCurveScale.normalizedY(for: 3) == 0.25, "positive midpoint is centered in upper half")
        require(NodebayEqualizerCurveScale.normalizedY(for: 0) == 0.5, "flat maps to visual center")
        require(NodebayEqualizerCurveScale.normalizedY(for: -6) == 0.75, "negative midpoint is centered in lower half")
        require(NodebayEqualizerCurveScale.normalizedY(for: -12) == 1, "maximum reduction maps to bottom")
        require(NodebayEqualizerCurveScale.gain(atNormalizedY: 0.5) == 0, "visual center maps back to flat")
        require(NodebayEqualizerCurveScale.gain(atNormalizedY: 0.25) == 3, "upper half maps back to boost")
        require(NodebayEqualizerCurveScale.gain(atNormalizedY: 0.75) == -6, "lower half maps back to reduction")

        let shaped = NodebayEqualizerProfile(gains: [1, 3, -2, 4, 6])
        require(shaped.gain(for: .bass) == 2, "bass handle averages low bands")
        require(shaped.gain(for: .mid) == -2, "mid handle maps center band")
        require(shaped.gain(for: .treble) == 5, "treble handle averages high bands")
        require(
            shaped.setting(-5, for: .bass).gains == [-5, -5, -2, 4, 6],
            "bass handle updates both low bands"
        )
        require(
            shaped.setting(20, for: .treble).gains == [1, 3, -2, 6, 6],
            "tone handle clamps both high bands"
        )
        let spotify = "com.spotify.client"
        let roots = ["/Applications/Spotify.app"]
        require(NodebayAudioProcessIdentity.matches(bundleID: spotify, bundlePath: nil,
            requestedID: spotify, applicationPaths: roots), "Spotify process identity")
        require(NodebayAudioProcessIdentity.matches(bundleID: spotify + ".helper", bundlePath: nil,
            requestedID: spotify, applicationPaths: roots), "Spotify helper identity")
        require(NodebayAudioProcessIdentity.matches(bundleID: nil,
            bundlePath: "/Applications/Spotify.app/Contents/Frameworks/Spotify Helper.app",
            requestedID: spotify, applicationPaths: roots), "nested renderer without Core Audio bundle ID")
        require(!NodebayAudioProcessIdentity.matches(bundleID: "com.spotify.clientOther", bundlePath: nil,
            requestedID: spotify, applicationPaths: roots), "similar bundle cannot match")
        require(!NodebayAudioProcessIdentity.matches(bundleID: nil, bundlePath: "/Applications/Spotify.app.fake",
            requestedID: spotify, applicationPaths: roots), "sibling path cannot match")
        require(!NodebayAudioProcessIdentity.matches(bundleID: "com.apple.Music", bundlePath: nil,
            requestedID: spotify, applicationPaths: roots), "unrelated app cannot match")

        var health = NodebayProcessAudioHealth()
        require(health.decision(now: 0, startedAt: 0, routed: false) == .wait, "startup preserves passthrough")
        health.lastCallback = 2
        require(health.decision(now: 2, startedAt: 0, routed: false) == .wait, "callbacks without audio do not mute")
        health.lastSignal = 2
        require(health.decision(now: 2.1, startedAt: 0, routed: false) == .activate, "usable signal permits routing")
        health.lastCallback = 3.2
        require(health.decision(now: 3.2, startedAt: 0, routed: true) == .restore, "lost audio restores passthrough")
        health.lastCallback = 13
        health.lastSignal = nil
        require(health.decision(now: 13, startedAt: 0, routed: false) == .fail, "zero buffers time out without muting")
        health.lastSignal = 10
        require(health.decision(now: 14.1, startedAt: 14, routed: false) == .fail, "stalled callback fails promptly")
        health.lastCallback = 15
        health.lastSignal = 15
        health.invalidLayout = true
        require(health.decision(now: 15, startedAt: 14, routed: false) == .fail, "bad layout never routes")
        print("Nodebay equalizer core checks passed")
    }
}
