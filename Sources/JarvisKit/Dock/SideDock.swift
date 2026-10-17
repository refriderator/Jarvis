import CoreGraphics
import Foundation

/// The left or right edge of a display, where held windows wait.
public enum ScreenSide: String, Sendable, Equatable, CaseIterable {
    case left
    case right
}

/// Where windows held on the sides go. A held window stays a real window on its own desktop, slid off the
/// display's edge with `sliver` left showing (macOS won't keep a window entirely off its displays). Hovering
/// the edge shows Jarvis's own cards for them; the window itself comes back out when one is picked.
/// All frames are AppKit screen coordinates (origin bottom-left, y up).
public enum SideDock {
    /// How much of a parked window stays on its display.
    public static let sliver: CGFloat = 1
    /// How close to the edge the pointer must come to show the cards.
    public static let edgeZone: CGFloat = 3
    /// Held windows per desktop, the same as the notch's strip.
    public static let maxWindows = NotchDock.maxApps
    public static let cardWidth: CGFloat = 220
    public static let cardHeight: CGFloat = 138
    public static let cardGap: CGFloat = 10
    /// A popped window's size, about System Settings' (smaller on a small display), and its distance from the edge.
    public static let popSize = CGSize(width: 720, height: 640)
    public static let popInset: CGFloat = 10
    /// A popped window slides back once the pointer is this far off it for `leaveGrace` seconds, so overshooting
    /// its edge doesn't send it away.
    public static let leaveMargin: CGFloat = 24
    public static let leaveGrace: TimeInterval = 0.3
    /// The cards' distance from the edge once slid out.
    public static let cardInset: CGFloat = 10

    /// The sides of `screen` with no other display against them: parking off an edge another display touches
    /// would put the window on that display instead.
    public static func freeSides(of screen: CGRect, others: [CGRect]) -> [ScreenSide] {
        ScreenSide.allCases.filter { side in
            let strip = side == .left
                ? CGRect(x: screen.minX - 2, y: screen.minY, width: 2, height: screen.height)
                : CGRect(x: screen.maxX, y: screen.minY, width: 2, height: screen.height)
            return !others.contains { $0 != screen && $0.intersects(strip) }
        }
    }

    /// The side a window goes to: the one its middle is nearer, unless that side isn't free.
    public static func side(for frame: CGRect, on screen: CGRect, free: [ScreenSide]) -> ScreenSide? {
        let nearer: ScreenSide = frame.midX < screen.midX ? .left : .right
        return free.contains(nearer) ? nearer : free.first
    }

    /// A window of `frame` slid off `side` of `screen`, kept at its height (inside `visible`, the screen minus menu
    /// bar and Dock), with `sliver` showing. macOS gives a window that's off every display to the display nearest
    /// it, and that display's desktop, so a wide window parked beside a corner of another display (`others`) would
    /// end up held by neither; it's made narrower until its middle is nearer `screen`.
    public static func parked(_ frame: CGRect, side: ScreenSide, screen: CGRect, visible: CGRect,
                              others: [CGRect] = []) -> CGRect {
        var width = frame.width
        while width > minParkedWidth, nearest(to: placed(width), among: others + [screen]) != screen {
            width = max(minParkedWidth, width - 40)
        }
        return placed(width)

        func placed(_ width: CGFloat) -> CGRect {
            let x = side == .left ? screen.minX - width + sliver : screen.maxX - sliver
            return CGRect(x: x, y: clampedY(frame, in: visible), width: width, height: frame.height)
        }
    }

    /// Narrower than this, a parked window is left as is (apps have their own minimum anyway).
    static let minParkedWidth: CGFloat = 200

    /// The display whose edge is closest to `frame`'s middle.
    public static func nearest(to frame: CGRect, among screens: [CGRect]) -> CGRect? {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { distance(middle, $0) < distance(middle, $1) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// A held window clicked with Quick Dock off: popped out of `side`, over the window in front, `popInset`
    /// from the edge, centred top to bottom. It's `size` (the size it was last resized to there) or `popSize`,
    /// shrunk to fit the display.
    public static func popped(_ size: CGSize? = nil, side: ScreenSide, visible: CGRect) -> CGRect {
        let room = visible.insetBy(dx: popInset, dy: popInset)
        let wanted = size ?? popSize
        let size = CGSize(width: min(wanted.width, room.width), height: min(wanted.height, room.height))
        return onScreen(CGRect(origin: CGPoint(x: 0, y: (visible.midY - size.height / 2).rounded()), size: size),
                        side: side, visible: visible)
    }

    /// `frame` moved (not resized) to sit `popInset` from `side`, inside `visible` top to bottom. Apps keep their
    /// own minimum size, so a popped window can come out bigger than asked; this keeps all of it on the display.
    public static func onScreen(_ frame: CGRect, side: ScreenSide, visible: CGRect) -> CGRect {
        let x = side == .left ? visible.minX + popInset : visible.maxX - popInset - frame.width
        return CGRect(x: max(x, visible.minX), y: clampedY(frame, in: visible), width: frame.width, height: frame.height)
    }

    /// The cards for `count` windows on `side`, top to bottom, centred down the edge. Slid out when `showing`,
    /// otherwise just off the edge (so they slide in from it).
    public static func cards(count: Int, side: ScreenSide, visible: CGRect, showing: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let room = (visible.height - cardGap * CGFloat(count + 1)) / CGFloat(count)
        let height = min(cardHeight, room)
        let total = height * CGFloat(count) + cardGap * CGFloat(count - 1)
        let top = visible.midY + total / 2
        let x: CGFloat = switch (side, showing) {
        case (.left, true): visible.minX + cardInset
        case (.left, false): visible.minX - cardWidth
        case (.right, true): visible.maxX - cardInset - cardWidth
        case (.right, false): visible.maxX
        }
        return (0..<count).map { index in
            CGRect(x: x, y: (top - height - CGFloat(index) * (height + cardGap)).rounded(),
                   width: cardWidth, height: height)
        }
    }

    /// The pointer is at the edge where cards wait (and between the menu bar and the Dock).
    public static func atEdge(_ pointer: CGPoint, side: ScreenSide, screen: CGRect, visible: CGRect,
                              zone: CGFloat = edgeZone) -> Bool {
        guard pointer.y >= visible.minY, pointer.y <= visible.maxY else { return false }
        return side == .left ? pointer.x <= screen.minX + zone : pointer.x >= screen.maxX - zone
    }

    /// A window dragged by its title bar and let go here goes to that side (a little more room than hovering).
    public static func dropSide(_ pointer: CGPoint, screen: CGRect, visible: CGRect, free: [ScreenSide]) -> ScreenSide? {
        free.first { atEdge(pointer, side: $0, screen: screen, visible: visible, zone: 8) }
    }

    /// A card dragged into the middle third of a display is let go of there, not moved to a side.
    public static func inMiddle(_ pointer: CGPoint, screen: CGRect) -> Bool {
        abs(pointer.x - screen.midX) < screen.width / 6
    }

    /// Where a window of `size` let go of in the middle goes (and the outline shown while it's dragged there):
    /// centred on the display, shrunk to fit.
    public static func released(_ size: CGSize, visible: CGRect) -> CGRect {
        let room = visible.insetBy(dx: popInset, dy: popInset)
        let fit = CGSize(width: min(size.width, room.width), height: min(size.height, room.height))
        return CGRect(x: (visible.midX - fit.width / 2).rounded(), y: (visible.midY - fit.height / 2).rounded(),
                      width: fit.width, height: fit.height)
    }

    /// A card dragged over `screen` lands on the side of the half the pointer is in (the other one if that side
    /// isn't free), among the `count` cards already there: the index of the slot the pointer is level with.
    public static func cardDrop(_ pointer: CGPoint, screen: CGRect, visible: CGRect, free: [ScreenSide],
                                count: (ScreenSide) -> Int) -> (side: ScreenSide, index: Int)? {
        let half: ScreenSide = pointer.x < screen.midX ? .left : .right
        guard let side = free.contains(half) ? half : free.first else { return nil }
        let n = count(side)
        let slots = cards(count: n + 1, side: side, visible: visible, showing: true)
        let index = slots.firstIndex { pointer.y >= $0.minY } ?? n
        return (side, min(index, n))
    }

    private static func clampedY(_ frame: CGRect, in visible: CGRect) -> CGFloat {
        guard frame.height < visible.height else { return visible.maxY - frame.height }
        return min(max(frame.minY, visible.minY), visible.maxY - frame.height)
    }
}
