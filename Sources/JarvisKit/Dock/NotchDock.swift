import CoreGraphics
import Foundation

/// Another app's window set aside in the notch, like Stage Manager's strip: minimized, its app's icon waiting
/// beside the notch. Minimized windows come back on the desktop they left, so each belongs to one desktop and
/// only shows there.
public struct HeldApp: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var pid: Int32
    public var appName: String
    /// The desktop (Space) it was set aside on; nil if that couldn't be told (then it shows everywhere).
    public var desktop: Int?
    /// Waiting off a side of the screen (`SideDock`) rather than minimized: shown here too, so the notch says
    /// what it holds, and clicked it does what its card does.
    public var onSide: Bool

    public init(id: UUID = UUID(), pid: Int32, appName: String, desktop: Int? = nil, onSide: Bool = false) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.desktop = desktop
        self.onSide = onSide
    }
}

/// What a window dragged into the drop box becomes.
public enum DockCatchKind: Sendable, Equatable {
    /// A Finder window: its folder opens in the Finder tab.
    case folder
    /// Any other window: minimized, its app's icon waiting in the tab beside the closed notch.
    case app
}

/// What the dropdown shows under the time, picked with the tabs beside the notch.
public enum PanelTab: String, Sendable, CaseIterable {
    /// Calendar events, what's due, and timers.
    case today
    /// A folder Jarvis draws itself, to drop files in and drag them out.
    case finder
    /// CPU, memory, network and the busiest processes.
    case monitor
    /// A small browser: tabs, back and forward, and a start page of bookmarks.
    case browser
}

/// The dropdown's tab and what the notch is holding. Jarvis draws all of it in its own panel, which is on every
/// desktop and above every window, so it moves with the notch and Mission Control leaves it alone.
public struct NotchDock: Sendable, Equatable {
    public var tab: PanelTab = .today
    /// The Web tab as deep as Large's video, instead of the Finder tab's depth.
    public var browserLarge = false
    /// The Web tab's page showing has a video full screen (in the page; see `PageFullscreen`).
    public var browserFullscreen = false
    /// Minimized windows, up to `maxApps` per desktop.
    public var apps: [HeldApp] = []
    public static let maxApps = 6
    /// The desktop showing now (nil if it can't be told).
    public var desktop: Int?
    /// A window is being dragged by its title bar: the open dropdown shows an empty drop box.
    public var dragging: DockCatchKind?
    /// ...and it's on the box: its app's icon fades in, and letting go now holds it.
    public var catching = false
    /// Keep the dropdown open, on any tab, even when the pointer leaves.
    public var keep = KeepMode.off {
        didSet { if keep != .large { keepInfo = keep } }
    }
    /// The last thing Keep Info was set to (on or off): Large doesn't change it, and leaving Large goes back to it.
    public private(set) var keepInfo = KeepMode.off
    /// With a video held, the tab's content stays folded away (just the time, the video and the music) until a
    /// tab is clicked; clicking the chosen tab again folds it away again.
    public var contentHidden = false

    public init() {}

    /// The held apps on the desktop showing now, oldest first.
    public var shownApps: [HeldApp] { apps.filter { $0.desktop == nil || desktop == nil || $0.desktop == desktop } }
    public var isFull: Bool { shownApps.count >= Self.maxApps }

    /// The held apps set aside on `desktop`, oldest first (with nil, the ones whose desktop couldn't be told).
    public func apps(on desktop: Int?) -> [HeldApp] { apps.filter { $0.desktop == desktop } }

    /// "2" for the second held window of the same app on this desktop, nil for the first, so they can be told apart.
    public func number(of app: HeldApp) -> Int? {
        let same = shownApps.filter { $0.pid == app.pid }
        guard same.count > 1, let index = same.firstIndex(where: { $0.id == app.id }) else { return nil }
        return index + 1
    }
    /// The tab's content (or the drop box) takes the "TODAY" list's fixed-height place.
    public var showsShelf: Bool { tab != .today || dragging != nil }
    /// Icons in the tab beside the closed notch.
    public var tabSlots: Int { shownApps.count }
}

/// The Keep button's three settings.
public enum KeepMode: Sendable, Equatable {
    case off
    /// The dropdown stays open.
    case on
    /// With a video held: the dropdown stays open as just the video, bigger, until the pointer comes over it.
    case large

    /// The next one on a click of Keep Info: on and off. (Large comes from the video's ↓ tab, not from here.)
    public var next: KeepMode {
        self == .off ? .on : .off
    }
}

/// Decides whether a dragged window is "on" something. It catches close to one region but only lets go once
/// well outside a bigger one, so a pointer resting on the edge doesn't flicker between the two: hysteresis,
/// like a Schmitt trigger. Two of these run while a window is dragged: one opens the dropdown (catch at the
/// notch, let go outside the whole dropdown), one fills the drop box (catch near it, let go a bit further out).
public struct DockCatch: Sendable, Equatable {
    /// How close the pointer must come to catch.
    public let catchMargin: CGFloat
    /// How far it must go to let go again.
    public let releaseMargin: CGFloat

    public private(set) var caught = false

    public init(catchMargin: CGFloat = 12, releaseMargin: CGFloat = 70) {
        self.catchMargin = catchMargin
        self.releaseMargin = releaseMargin
    }

    /// Feeds the pointer's position; returns true when `caught` changed.
    @discardableResult
    public mutating func update(pointer: CGPoint, catchIn: CGRect, releaseOutside: CGRect) -> Bool {
        let zone = caught ? releaseOutside.insetBy(dx: -releaseMargin, dy: -releaseMargin)
                          : catchIn.insetBy(dx: -catchMargin, dy: -catchMargin)
        let inside = zone.contains(pointer)
        guard inside != caught else { return false }
        caught = inside
        return true
    }
}

/// AppKit puts the origin at the bottom-left of the main display with y going up; Accessibility puts it at
/// the top-left with y going down. The flip is its own inverse.
public enum ScreenSpace {
    public static func flip(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flip(_ point: CGPoint, mainHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainHeight - point.y)
    }
}
