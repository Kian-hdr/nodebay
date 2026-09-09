import AppKit
import SwiftUI

private struct Frames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private final class Result { var frames: [String: CGRect] = [:] }
private struct Fixture: View {
    let result: Result
    let lyrics: Bool
    let legacy: Bool
    func mark<V: View>(_ name: String, @ViewBuilder content: () -> V) -> some View {
        content().background(GeometryReader { g in
            Color.clear.preference(key: Frames.self, value: [name: g.frame(in: .named("player"))])
        })
    }
    var info: some View {
        mark("info") {
            VStack(alignment: .leading, spacing: 0) {
                Text("Spotify · Playing").frame(height: 20).padding(.bottom, 6)
                Text("A very long media title that must not affect row separation").font(.headline).lineLimit(1)
                HStack(spacing: 8) {
                    Text("Artist").font(.headline).lineLimit(1)
                    if lyrics { Text("An optional lyric line").font(.subheadline).lineLimit(1) }
                }
            }
        }
    }
    var timeline: some View {
        mark("timeline") { VStack(spacing: 2) {
            Rectangle().frame(height: 10)
            HStack { Text("0:12"); Spacer(); Text("4:00") }.font(.caption)
        }.frame(height: 26) }
    }
    var controls: some View {
        mark("controls") { HStack {
            Button("Previous") {}; Button("Play") {}; Button("Next") {}; Spacer(); Button("EQ") {}
        }.frame(height: 40) }
    }
    var body: some View {
        Group {
            if legacy {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { _ in VStack(alignment: .leading, spacing: 4) { info; timeline } }
                        .padding(.top, 10)
                    controls
                }
            } else {
                MusicPlayerColumn { info } timeline: { timeline } controls: { controls }
            }
        }
        .coordinateSpace(name: "player")
        .onPreferenceChange(Frames.self) { result.frames = $0 }
    }
}
@main struct Harness {
    @MainActor static func main() {
        let legacy = CommandLine.arguments.contains("--legacy")
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var cases = 0
        for width in [460.0, 300.0, 200.0] {
            for lyrics in [false, true] {
                let result = Result()
                let host = NSHostingView(rootView: Fixture(result: result, lyrics: lyrics, legacy: legacy))
                let height: CGFloat = 138
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: width, height: height)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.10))
                guard let info = result.frames["info"], let timeline = result.frames["timeline"], let controls = result.frames["controls"] else { fatalError("Missing actual SwiftUI geometry") }
                precondition(info.maxY <= timeline.minY, "Metadata overlaps timeline")
                precondition(timeline.maxY + 4 <= controls.minY, "Timeline overlaps playback icons")
                precondition(controls.maxY <= height + 0.5, "Playback icons extend beyond content budget")
                cases += 1
                window.contentView = nil
            }
        }
        print("PASS: \(cases) native SwiftUI layout cases; optional lyrics, narrow/default widths, no overlap")
    }
}
