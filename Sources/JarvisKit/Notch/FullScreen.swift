import CoreGraphics

/// An app full screen on a display without a hardware notch: there's no menu bar there, so the pill, its tab and
/// a tray would sit over the app's own tabs and toolbar. They hide, and come out only when the pointer is pushed
/// against the top edge above them (the edge stops the pointer, so that strip is easy to hit however thin it is).
public enum FullScreen {
    /// An ordinary window covering a whole display (both in the same coordinates). Full screen, an app's window is
    /// exactly the display; a big window on an ordinary desktop stops under the menu bar.
    public static func covers(_ window: CGRect, display: CGRect) -> Bool {
        abs(window.minX - display.minX) < 1 && abs(window.minY - display.minY) < 1
            && abs(window.width - display.width) < 1 && abs(window.height - display.height) < 1
    }

    /// How deep the strip along the top edge is.
    public static let edgeDepth: CGFloat = 2

    /// The strip along the top of `screen` (origin bottom-left, y up) that brings back what's hidden there, as
    /// wide as `span`.
    public static func edge(of screen: CGRect, under span: CGRect) -> CGRect {
        CGRect(x: span.minX, y: screen.maxY - edgeDepth, width: span.width, height: edgeDepth + 1)
    }
}
