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
        mark("controls") {
            MusicControlStrip(minimumWidth: 0) {
                HStack(spacing: 6) {
                    HoverButton(icon: "backward.fill") {}
                    HoverButton(icon: "play.fill", scale: .large) {}
                    HoverButton(icon: "forward.fill") {}
                    Spacer()
                    HoverButton(icon: "slider.vertical.3") {}
                }
            }
        }
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

private struct ControlStripFixture: View {
    let result: Result
    let width: CGFloat
    let legacyIndicators: Bool

    private var buttons: some View {
        HStack(spacing: 6) {
            HoverButton(icon: "shuffle") {}
            HoverButton(icon: "backward.fill") {}
            HoverButton(icon: "play.fill", scale: .large) {}
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: Frames.self,
                        value: ["play": geometry.frame(in: .named("strip"))])
                })
            HoverButton(icon: "forward.fill") {}
            HoverButton(icon: "repeat") {}
            HoverButton(icon: "heart") {}
            HoverButton(icon: "goforward.15") {}
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        Group {
            if legacyIndicators {
                LegacyMusicControlStrip(minimumWidth: width) { buttons }
            } else {
                MusicControlStrip(minimumWidth: width) { buttons }
            }
        }
        .frame(width: width, height: 40)
        .coordinateSpace(name: "strip")
        .onPreferenceChange(Frames.self) { result.frames = $0 }
    }
}

@main struct Harness {
    @MainActor private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    @MainActor private static func measureControlStrips(legacyIndicators: Bool) {
        var cases = 0
        for style in [NSScroller.Style.legacy, .overlay] {
            for width: CGFloat in [360, 180] {
                let result = Result()
                let host = NSHostingView(rootView: ControlStripFixture(
                    result: result, width: width, legacyIndicators: legacyIndicators))
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 40),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host
                host.frame = CGRect(x: 0, y: 0, width: width, height: 40)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let matches = scrollViews(in: host)
                precondition(matches.count == 1, "Expected the production strip's native NSScrollView")
                let scroll = matches[0]
                // Force only this test view to the mouse/legacy or trackpad/overlay
                // mode. Never change AppleShowScrollBars or any user default.
                scroll.scrollerStyle = style
                scroll.autohidesScrollers = false
                scroll.tile()
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                precondition(scroll.scrollerStyle == style, "Native strip must retain the requested scroller style")
                let viewport = scroll.contentView.bounds
                guard let play = result.frames["play"], let document = scroll.documentView else {
                    fatalError("Missing actual playback-button or scroll-document geometry")
                }
                print("Strip style=\(style.rawValue) width=\(width) viewport=\(viewport.height) document=\(document.frame.size) horizontal=\(scroll.hasHorizontalScroller) play=\(play)")
                fflush(stdout)
                precondition(viewport.height >= 39.5,
                             "Horizontal scroller reduced the 40pt playback viewport")
                precondition(abs(play.height - 40) <= 0.5 && play.minY >= -0.5 && play.maxY <= 40.5,
                             "Actual large playback button is vertically clipped")
                if width < 256 {
                    let maximumOffset = document.frame.width - viewport.width
                    precondition(maximumOffset > 20, "Overflow fixture must have a real horizontal scroll range")
                    scroll.contentView.scroll(to: CGPoint(x: maximumOffset, y: viewport.origin.y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    precondition(scroll.contentView.bounds.origin.x > 20,
                                 "Hiding indicators must preserve native horizontal scrolling")
                } else {
                    precondition(document.frame.width <= viewport.width + 0.5,
                                 "Normal-width fixture must fit without horizontal overflow")
                }
                cases += 1
                window.contentView = nil
            }
        }
        print("PASS: \(cases) native control-strip cases; legacy/overlay scrollers, full40pt viewport, overflow scrolling")
    }

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
        measureControlStrips(legacyIndicators: CommandLine.arguments.contains("--legacy-scrollers"))
    }
}
