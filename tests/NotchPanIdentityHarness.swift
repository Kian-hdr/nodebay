import AppKit
import SwiftUI
import Defaults

// Only the pan view's Defaults dependency, not app state. The fixture never
// emits scroll events or writes this preference.
extension Defaults.Keys {
    static let normalizeGestureDirection = Key<Bool>("nodebay.test.pan.direction", default: true)
}

@MainActor final class PanFixture: ObservableObject {
    @Published var enabled = true
    var made = 0
    var removed = 0
}

struct IdentityProbe: NSViewRepresentable {
    let fixture: PanFixture
    func makeNSView(context: Context) -> NSView { fixture.made += 1; return NSView() }
    func updateNSView(_ view: NSView, context: Context) {}
    func makeCoordinator() -> PanFixture { fixture }
    static func dismantleNSView(_ view: NSView, coordinator: PanFixture) { coordinator.removed += 1 }
}

struct PanFixtureView: View {
    @ObservedObject var fixture: PanFixture
    var legacy = false
    @ViewBuilder var body: some View {
        if legacy {
            // Reproduce the previous view-identity bug with the real wrapper.
            IdentityProbe(fixture: fixture)
                .frame(width: 320, height: 190)
                .conditionalModifier(fixture.enabled) { view in
                    view.panGesture(direction: .down) { _, _ in }
                }
        } else {
            IdentityProbe(fixture: fixture)
            .frame(width: 320, height: 190)
            .panGesture(direction: .down, enabled: fixture.enabled) { _, _ in }
            .panGesture(direction: .up, enabled: fixture.enabled) { _, _ in }
            .panGesture(direction: .left, enabled: fixture.enabled) { _, _ in }
            .panGesture(direction: .right, enabled: fixture.enabled) { _, _ in }
        }
    }
}

@main struct NotchPanIdentityHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let legacy = CommandLine.arguments.contains("--legacy")
        let fixture = PanFixture()
        let host = NSHostingView(rootView: PanFixtureView(fixture: fixture, legacy: legacy))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 190),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        func update() {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        update()
        precondition(fixture.made == 1, "Initial native subtree must be created exactly once")
        for _ in 0..<10 {
            fixture.enabled.toggle()
            update()
            if !legacy {
                precondition(fixture.made == 1 && fixture.removed == 0,
                             "Toggling Chat gestures must not replace the native notch subtree")
            }
        }
        if legacy {
            precondition(fixture.made > 1 && fixture.removed > 0, "Must reproduce the legacy replacement")
            print("REPRODUCED: conditional pan wrapper replaced native subtree \(fixture.removed) times")
        } else {
            print("PASS: ten pan toggles preserve native subtree identity")
        }
    }
}
