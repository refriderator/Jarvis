import CoreGraphics
import JarvisKit
import Testing

struct FullScreenTests {
    let display = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test func fullScreenWindowCoversItsDisplay() {
        #expect(FullScreen.covers(display, display: display))
    }

    /// A zoomed window on an ordinary desktop stops under the menu bar.
    @Test func bigWindowUnderTheMenuBarDoesNot() {
        let zoomed = CGRect(x: 1512, y: 25, width: 2560, height: 1415)
        #expect(!FullScreen.covers(zoomed, display: display))
    }

    @Test func windowOnAnotherDisplayDoesNot() {
        #expect(!FullScreen.covers(CGRect(x: 0, y: 0, width: 2560, height: 1440), display: display))
    }

    @Test func edgeIsTheTopStripAboveTheSpan() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let pill = CGRect(x: 890, y: 1058, width: 140, height: 22)
        let edge = FullScreen.edge(of: screen, under: pill)
        #expect(edge.minX == pill.minX && edge.width == pill.width)
        #expect(edge.contains(CGPoint(x: 960, y: 1079)))
        #expect(!edge.contains(CGPoint(x: 960, y: 1070)))
    }
}
