import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct NotchDragRegionHarness {
    static func main() {
        let window = CGRect(x: 100, y: 800, width: 640, height: 210)
        let region = NotchDragRegion.closed(
            windowFrame: window,
            notchSize: CGSize(width: 220, height: 38)
        )

        require(region.width == 236, "closed width should add only narrow horizontal padding")
        require(region.height == 44, "closed height should add only narrow lower padding")
        require(region.maxY == window.maxY, "region should remain attached to the display edge")
        require(region.contains(CGPoint(x: window.midX, y: window.maxY - 20)), "visible notch must activate")
        require(!region.contains(CGPoint(x: window.midX, y: window.maxY - 80)), "browser content below notch must not activate")
        require(!region.contains(CGPoint(x: window.minX + 20, y: window.maxY - 20)), "wide transparent window edge must not activate")

        let hidden = NotchDragRegion.closed(
            windowFrame: CGRect(x: -900, y: 0, width: 640, height: 210),
            notchSize: CGSize(width: 185, height: 0)
        )
        require(hidden.height == 16, "zero-height mode should retain a small intentional target")
        require(hidden.midX == -580, "negative external-display coordinates must be preserved")

        print("NotchDragRegionHarness: PASS")
    }
}
