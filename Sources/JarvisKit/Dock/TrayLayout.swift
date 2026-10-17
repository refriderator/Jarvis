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
/// Without a hardware notch it hangs from the middle of the menu bar and opens downward. With one (the Mac's own
/// display while the notch is on another), it slides out sideways from behind the hardware notch, its grid's two
/// rows sharing the notch's height, and slides back behind it to hide.
public struct TrayLayout: Sendable, Equatable {
    public var screen: CGRect
    public var menuBarHeight: CGFloat
    /// The display's hardware notch; nil on a display without one.
    public var hardwareNotch: CGRect?

    public static let columns = 3
    public static let rows = NotchDock.maxApps / columns
    /// A place in the grid hanging below the menu bar, and the room around the grid.
    public static let slot = CGSize(width: 52, height: 44)
    public static let padding: CGFloat = 14
    /// The resting notch without a hardware one.
    public static let dotWidth: CGFloat = 56
    /// Beside a hardware notch: each column's width, how far the dot shows past it, and the room at the end.
    public static let besideSlot: CGFloat = 30
    public static let besideDot: CGFloat = 20
    public static let besideEnd: CGFloat = 12

    public init(screen: CGRect, menuBarHeight: CGFloat, hardwareNotch: CGRect? = nil) {
        self.screen = screen
        self.menuBarHeight = menuBarHeight > 4 ? menuBarHeight : 24
        self.hardwareNotch = hardwareNotch
    }

    /// The tray's shape in `stage`.
    public func frame(for stage: TrayStage) -> CGRect {
        if let notch = hardwareNotch {
            let past: CGFloat = switch stage {
            case .hidden: 0
            case .dot: Self.besideDot
            case .open: CGFloat(Self.columns) * Self.besideSlot + Self.besideEnd
            }
            return CGRect(x: notch.minX, y: notch.minY, width: notch.width + past, height: notch.height)
        }
        let size: CGSize = switch stage {
        case .hidden: CGSize(width: Self.dotWidth, height: 0)
        case .dot: CGSize(width: Self.dotWidth, height: menuBarHeight)
        case .open: CGSize(width: CGFloat(Self.columns) * Self.slot.width + 2 * Self.padding,
                           height: menuBarHeight + CGFloat(Self.rows) * Self.slot.height + Self.padding)
        }
        return CGRect(x: (screen.midX - size.width / 2).rounded(), y: screen.maxY - size.height,
                      width: size.width, height: size.height)
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
