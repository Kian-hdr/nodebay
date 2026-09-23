import Foundation

@main
struct NotchHoverReconciliationHarness {
    static func main() {
        var policy = NotchHoverDismissal()
        // Missing exit event: only live pointer samples are required.
        assert(!policy.shouldClose(now: 10, pointerInside: false, interactionActive: false))
        assert(!policy.shouldClose(now: 10.1, pointerInside: false, interactionActive: false))
        assert(policy.shouldClose(now: 10.3, pointerInside: false, interactionActive: false))
        // Pointer reentry cancels a pending exit.
        assert(!policy.shouldClose(now: 11, pointerInside: true, interactionActive: false))
        assert(!policy.shouldClose(now: 20, pointerInside: false, interactionActive: false))
        assert(!policy.shouldClose(now: 20.1, pointerInside: true, interactionActive: false))
        assert(!policy.shouldClose(now: 21, pointerInside: false, interactionActive: false))
        assert(policy.shouldClose(now: 21.3, pointerInside: false, interactionActive: false))
        // Sharing, popovers, menus and button-down drags hold the panel open;
        // releasing a hold closes it even if no new hover event arrives.
        for _ in 0..<4 {
            assert(!policy.shouldClose(now: 30, pointerInside: false, interactionActive: true))
            assert(!policy.shouldClose(now: 100, pointerInside: false, interactionActive: true))
            assert(!policy.shouldClose(now: 101, pointerInside: false, interactionActive: false))
            assert(!policy.shouldClose(now: 101.1, pointerInside: false, interactionActive: false))
            assert(policy.shouldClose(now: 101.3, pointerInside: false, interactionActive: false))
        }
        // Another display has independent dismissal state.
        var otherDisplay = NotchHoverDismissal()
        assert(!otherDisplay.shouldClose(now: 101.3, pointerInside: true, interactionActive: false))
        assert(policy.shouldClose(now: 101.4, pointerInside: false, interactionActive: false))
        var activation = NotchHoverActivation()
        func open(_ now: TimeInterval, closed: Bool, expanded: Bool, enabled: Bool = true) -> Bool {
            activation.shouldOpen(now: now, insideClosedRegion: closed,
                                  insideExpandedRegion: expanded, enabled: enabled, dwell: 0.3)
        }
        assert(!open(0, closed: true, expanded: true))
        assert(!open(0.2, closed: true, expanded: true))
        assert(open(0.31, closed: true, expanded: true))
        // Tracking churn and a close while the pointer is still at the top
        // cannot begin a second opening of the same pointer visit.
        assert(!open(0.7, closed: true, expanded: true))
        assert(!open(1.2, closed: true, expanded: true))
        assert(!open(1.3, closed: false, expanded: false))
        assert(!open(1.4, closed: true, expanded: true))
        assert(!open(1.6, closed: false, expanded: false))
        assert(!open(1.81, closed: false, expanded: false))
        assert(!open(1.9, closed: true, expanded: true))
        assert(open(2.21, closed: true, expanded: true))
        activation.markOpened()
        assert(!open(2.6, closed: true, expanded: true))
        print("Hover reconciliation: PASS")
    }
}
