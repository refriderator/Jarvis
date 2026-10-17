import CoreGraphics

/// How much of a tray shows (see `TrayLayout`).
public enum TrayStage: Int, Sendable, Equatable, Comparable {
    /// Nothing held there and no window on its way: no tray at all.
    case hidden
    /// Holding windows: a small notch with a white dot (beside the notch on a display that has one).
    case dot
    /// Hovered, or a window dragged to the top middle: the 2 × 3 grid, its empty places showing.
    case open

    public static func < (a: TrayStage, b: TrayStage) -> Bool { a.rawValue < b.rawValue }
}

/// The held-windows tray on a display that isn't the notch's: where it sits in each stage, and where a window
/// dragged by its title bar opens it and is caught. Screen coordinates (origin bottom-left, y up).
///
/// Open, it hangs from the middle of the top edge as a 2 × 3 grid, the same on every display: from the menu bar,
/// or from the hardware notch (the Mac's own display while the notch is on another), a little wider than that
/// notch so its shoulders curve into the menu bar like the notch's own. Resting with the dot, it hangs from the menu
/// bar too; beside a hardware notch it's a tab on the notch's right instead, like the apps' tab beside the notch,
/// sliding out from behind it.
public struct TrayLayout: Sendable, Equatable {
    public var screen: CGRect
    public var menuBarHeight: CGFloat
    /// The display's hardware notch; nil on a display without one.
    public var hardwareNotch: CGRect?

    public static let columns = 3
    public static let rows = NotchDock.maxApps / columns
    /// A place in the grid, and the room around the grid.
    public static let slot = CGSize(width: 52, height: 44)
    public static let padding: CGFloat = 14
    /// The resting tab's width without a hardware notch.
    public static let dotWidth: CGFloat = 56
    /// Beside a hardware notch: how far the tab starts under the notch (well clear of its round bottom corner), and
    /// how much of it shows past the notch (the flare included).
    public static let besideTuck: CGFloat = 20
    public static let besideOut: CGFloat = 26

    public init(screen: CGRect, menuBarHeight: CGFloat, hardwareNotch: CGRect? = nil) {
        self.screen = screen
        self.menuBarHeight = menuBarHeight > 4 ? menuBarHeight : 24
        self.hardwareNotch = hardwareNotch
    }

    /// What the open grid hangs from: the menu bar, or the hardware notch.
    public var hangsFrom: CGFloat { hardwareNotch?.height ?? menuBarHeight }

    /// Resting (and hidden) as a tab beside the hardware notch rather than hanging below the middle.
    public func isBeside(_ stage: TrayStage) -> Bool { hardwareNotch != nil && stage != .open }

    /// The tray's shape in `stage`.
    public func frame(for stage: TrayStage) -> CGRect {
        if let notch = hardwareNotch, stage != .open {
            // Hidden, only the part under the notch: it slides out from behind it.
            let width = Self.besideTuck + (stage == .dot ? Self.besideOut : 0)
            return CGRect(x: notch.maxX - Self.besideTuck, y: notch.minY, width: width, height: notch.height)
        }
        let grid = CGFloat(Self.columns) * Self.slot.width + 2 * Self.padding
        let size: CGSize = switch stage {
        case .hidden: CGSize(width: Self.dotWidth, height: 0)
        case .dot: CGSize(width: Self.dotWidth, height: menuBarHeight)
        // Wider than a hardware notch, so its corners aren't hidden behind the notch's round ones.
        case .open: CGSize(width: max(grid, (hardwareNotch?.width ?? 0) + 2 * Self.padding),
                           height: hangsFrom + CGFloat(Self.rows) * Self.slot.height + Self.padding)
        }
        let middle = hardwareNotch?.midX ?? screen.midX
        return CGRect(x: (middle - size.width / 2).rounded(), y: screen.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Everywhere the tray can be, in any stage: its window covers this, and takes clicks only over the tray.
    public var bounds: CGRect {
        [TrayStage.hidden, .dot, .open].map(frame(for:)).reduce(CGRect.null) { $0.union($1) }
    }

    /// A window's title bar dragged here (the top middle of the display) opens the tray.
    public var approachZone: CGRect {
        let middle = hardwareNotch?.midX ?? screen.midX
        return CGRect(x: middle - 280, y: screen.maxY - 150, width: 560, height: 150)
    }

    /// Let go here, the window is held: the open tray and plenty of room around it.
    public var dropZone: CGRect {
        let open = frame(for: .open)
        return CGRect(x: open.minX - 50, y: open.minY - 60, width: open.width + 100, height: open.height + 60)
    }
}
