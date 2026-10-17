import AppKit
import JarvisKit
import Observation
import os

/// Debug trail for window holding: `/usr/bin/log stream --level debug --predicate 'subsystem == "jarvis.dock"'`.
private let log = Logger(subsystem: "jarvis.dock", category: "dock")

/// Getting windows into the notch and back out, and the Finder tab's folder.
///
/// Drag a window by its title bar to the notch: the dropdown opens with a drop box, and anywhere over the
/// dropdown its app's icon fades into the box. Let go there: a Finder window closes and its folder opens in the Finder
/// tab; any other window is minimized and, once the dropdown has closed, its icon waits in the tab beside the
/// notch. Drag an icon out of that tab (on any desktop) and the app lifts into your pointer, then becomes its
/// window, still in your hand.
@MainActor
@Observable
final class DockController {
    /// The folder the Finder tab shows.
    private(set) var shown: URL
    private(set) var items: [ShelfItem] = []
    /// The icon of the window being dragged, for the drop box.
    private(set) var draggedIcon: NSImage?

    /// A file is being dragged out of the Finder tab, and where the pointer is; set by `NotchController`.
    @ObservationIgnored var onFileDrag: (CGPoint?) -> Void = { _ in }
    /// A window drag started or ended (the drop box came or went); set by `NotchController`.
    @ObservationIgnored var onWindowDrag: () -> Void = {}
    /// Whether a point is over another display's tray (lighting it up; nil clears it); set by `ScreenTrays`.
    @ObservationIgnored var overTray: (CGPoint?) -> Bool = { _ in false }
    /// The dragged window is over another display's tray.
    @ObservationIgnored private var overTrayNow = false
    /// Turns the drop box's frame in the panel into screen coordinates; set by `NotchController`.
    @ObservationIgnored var boxToScreen: (CGRect) -> CGRect = { $0 }
    /// Where the drop box is, in screen coordinates (nil while it isn't on screen).
    @ObservationIgnored private var box: CGRect?

    @ObservationIgnored let state: AppState
    @ObservationIgnored let windows: WindowControlling
    /// Windows held on the sides of the screen (minimized into the strip only when no side is free).
    @ObservationIgnored let sides: SideDockController
    /// The real windows behind `state.dock.apps`.
    @ObservationIgnored private var minimized: [UUID: ForeignWindow] = [:]
    /// The window under the pointer when the button went down, and where it was then.
    @ObservationIgnored private var pressed: (window: ForeignWindow, origin: CGPoint)?
    /// The pressed window has moved: this is a title-bar drag, not a drag inside the window.
    @ObservationIgnored private var movingWindow = false
    /// The dragged window reached the notch and opened the dropdown.
    @ObservationIgnored private var opener = DockCatch()
    /// ...and is on the drop box.
    @ObservationIgnored private var catcher = DockCatch(catchMargin: 16, releaseMargin: 40)
    @ObservationIgnored private var tracker: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private let ghost = DragGhost()
    /// Moves a window pulled out of the tab with the pointer until the button comes up.
    @ObservationIgnored private var follower: Timer?
    @ObservationIgnored private var pulled: (window: ForeignWindow, size: CGSize)?
    @ObservationIgnored private var jumpWatch: NSObjectProtocol?
    @ObservationIgnored private var spaceWatch: NSObjectProtocol?
    @ObservationIgnored private var pruner: Timer?
    @ObservationIgnored private var heldAt: [UUID: Date] = [:]
    /// Jarvis's own restores activate apps too; Quick Dock leaves those alone until then.
    @ObservationIgnored private(set) var ignoreActivationUntil = Date.distantPast

    /// How far down from a window's top edge counts as its title bar (unified toolbars are about 52 pt).
    static let titleBarDepth: CGFloat = 56

    init(state: AppState, windows: WindowControlling = AXWindowControl()) {
        self.state = state
        self.windows = windows
        sides = SideDockController(state: state, windows: windows)
        shown = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        // Each desktop has its own strip: follow the desktop showing, and drop windows brought back some
        // other way (the Dock, ⌘-Tab) or closed.
        state.updateDock { $0.desktop = Desktops.active(on: state.notchScreen?.displayID) }
        spaceWatch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.state.updateDock { $0.desktop = Desktops.active(on: self?.state.notchScreen?.displayID) }
                self?.prune()
            }
        }
        pruner = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
        sides.onPick = { [weak self] window in self?.restoreSide(window) }
        sides.onChange = { [weak self] parked in self?.showSides(parked) }
        sides.minimizedOn = { [weak self] desktop in
            self?.state.dock.apps(on: desktop).filter { !$0.onSide }.count ?? 0
        }
    }

    /// The windows held on the sides also show in the notch's strip (after the minimized ones), so it says what
    /// Jarvis is holding with Quick Dock on or off.
    private func showSides(_ parked: [ParkedWindow]) {
        let side = parked.map { item in
            HeldApp(id: item.id, pid: item.window.pid,
                    appName: NSRunningApplication(processIdentifier: item.window.pid)?.localizedName ?? "App",
                    desktop: item.desktop, onSide: true)
        }
        state.updateDock { dock in dock.apps = dock.apps.filter { !$0.onSide } + side }
    }

    /// Forgets held windows that aren't minimized any more (brought back another way) or were closed.
    private func prune() {
        let gone = state.dock.apps.filter { app in
            // The sides keep their own list (`SideDockController` prunes it).
            guard !app.onSide else { return false }
            guard let window = minimized[app.id] else { return true }
            // Minimizing takes a moment to show (macOS still says "not minimized" for about 0.3 s), so a window
            // set aside just now is left alone; pruning it then dropped the app straight after holding it.
            if let since = heldAt[app.id], Date().timeIntervalSince(since) < 3 { return false }
            return windows.frame(of: window) == nil || !windows.isMinimized(window)
        }
        guard !gone.isEmpty else { return }
        log.debug("prune: \(gone.map(\.appName).joined(separator: ", "), privacy: .public) brought back another way or closed")
        for app in gone { heldAt[app.id] = nil }
        for app in gone { minimized[app.id] = nil }
        state.updateDock { dock in dock.apps.removeAll { app in gone.contains { $0.id == app.id } } }
    }

    func boxMoved(_ frameInPanel: CGRect?) {
        box = frameInPanel.map(boxToScreen)
    }

    // MARK: Catching a window dragged onto the notch

    func mouseDown(at point: CGPoint) {
        guard tracker == nil else { return }
        pressed = nil
        movingWindow = false
        guard state.settings.holdWindows, AccessibilityAccess.isTrusted,
              let window = windows.window(at: point), let frame = windows.frame(of: window),
              // Only a press on the title bar or toolbar can move a window; anything lower (a file, text) is
              // a drag inside it, which must never open the drop box.
              point.y >= frame.maxY - Self.titleBarDepth else { return }
        log.debug("down: title bar of pid \(window.pid)")
        pressed = (window, frame.origin)
        opener = DockCatch()
        catcher = DockCatch(catchMargin: 16, releaseMargin: 40)
        // The WindowServer moves a window dragged by its title bar itself, so no app (and no event monitor)
        // gets drag events for it. So watch instead: about 60 times a second while the button is down.
        ticks = 0
        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
    }

    private func track() {
        guard let pressed else { return stopTracking() }
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return finishDrag() }
        let kind = kind(of: pressed.window)
        if !movingWindow {
            // A title-bar drag moves the window; a drag inside it (text, a file) never does. Give up after
            // two seconds of not moving, so long drags inside a window cost nothing.
            ticks += 1
            guard ticks < 120 else { return stopTracking() }
            guard let frame = windows.frame(of: pressed.window), frame.origin != pressed.origin else { return }
            // A seventh window on its desktop has nowhere to go, so it's not offered a box. Its own desktop: with
            // more than one display, that isn't always the notch's.
            let desktop = Desktops.of(pressed.window.element).first ?? state.dock.desktop
            guard kind == .folder || state.dock.apps(on: desktop).count < NotchDock.maxApps else { return stopTracking() }
            movingWindow = true
            log.debug("drag: window of pid \(pressed.window.pid) is moving")
            draggedIcon = NSRunningApplication(processIdentifier: pressed.window.pid)?.icon
        }
        let pointer = NSEvent.mouseLocation
        // Taken out of a side (popped out and dragged by its title bar): it's let go of in the middle of the display
        // (`SideDockController`'s outline) or moved to another edge, never put back in the notch or a tray, so
        // neither opens for it.
        let fromSide = sides.isParked(pressed.window)
        // Another display's tray takes apps (a Finder window's folder only goes to the notch's Finder tab).
        overTrayNow = !fromSide && kind == .app && overTray(pointer)
        // At the notch the dropdown opens with the box; well away from the whole dropdown it closes again.
        if !fromSide, opener.update(pointer: pointer, catchIn: state.layout.notch, releaseOutside: state.layout.frame(for: .open)) {
            log.debug("drag: dropdown \(self.opener.caught ? "opens" : "closes")")
            state.updateDock { $0.dragging = opener.caught ? kind : nil; $0.catching = false }
            onWindowDrag()
            if opener.caught {
                state.send(.summon)
            } else {
                catcher = DockCatch(catchMargin: 16, releaseMargin: 40)
                if !state.notch.locked { state.send(.dismiss) }
            }
        }
        // The whole dropdown is the drop area, so the window drops as soon as it's in: no going up to the notch
        // and back down to the box. The box shows the app's icon to say so.
        let dropdown = state.layout.frame(for: .open)
        guard opener.caught, catcher.update(pointer: pointer, catchIn: dropdown, releaseOutside: dropdown) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        state.updateDock { $0.catching = catcher.caught }
    }

    /// The button came up after a window drag: take it if it was let go on the box.
    private func finishDrag() {
        let window = movingWindow && (catcher.caught || overTrayNow) ? pressed?.window : nil
        let caughtByNotch = catcher.caught
        let opened = opener.caught
        let edge = movingWindow && !catcher.caught && !overTrayNow ? pressed?.window : nil
        stopTracking()
        if let edge { dropAtEdge(edge) }
        state.updateDock { $0.dragging = nil; $0.catching = false }
        if opened { onWindowDrag() }
        if let window {
            // Held where it was put: in the notch, on the notch's display; on a tray, on that tray's display.
            let pointer = NSEvent.mouseLocation
            let onto = caughtByNotch ? state.notchScreen : NSScreen.screens.first { $0.frame.contains(pointer) }
            kind(of: window) == .folder ? holdFolder(window) : holdApp(window, onto: onto)
        } else if opened, !state.layout.hotZone(for: .open).contains(NSEvent.mouseLocation), !state.notch.locked {
            // Opened by the drag but let go elsewhere: nothing to show.
            state.send(.dismiss)
        }
    }

    /// Let go at the left or right edge of a display: the window goes to that side. A moment first, so macOS's own
    /// tiling (for windows dragged to an edge) is done with it.
    private func dropAtEdge(_ window: ForeignWindow) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              let side = SideDock.dropSide(pointer, screen: screen.frame, visible: screen.visibleFrame,
                                           free: SideDock.freeSides(of: screen.frame, others: NSScreen.screens.map(\.frame)))
        else { return }
        log.debug("drop: at the \(side.rawValue, privacy: .public) edge")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            // A held window being used from the side can be moved to the other side too.
            sides.unpark(window)
            sides.park(window, makeRoom: true, side: side)
        }
    }

    private func stopTracking() {
        tracker?.invalidate()
        tracker = nil
        pressed = nil
        movingWindow = false
        draggedIcon = nil
        overTrayNow = false
        _ = overTray(nil)
    }

    private func kind(of window: ForeignWindow) -> DockCatchKind {
        NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier == FinderFolder.bundleID ? .folder : .app
    }

    // MARK: Holding

    private func holdFolder(_ window: ForeignWindow) {
        // The window being dragged is Finder's front window.
        guard let folder = FinderFolder.front() else {
            log.debug("hold: Finder window has no folder")
            return NSSound.beep()
        }
        windows.close(window)
        show(folder)
        state.updateDock { $0.tab = .finder }
    }

    /// Minimized, its icon in the tab. The dropdown stays until the pointer leaves it; the tab comes out after.
    /// Holding on the sides, it's slid off the nearer edge instead (minimized only when it can't be).
    /// `onto`: the display it was put in the notch or a tray of, when that isn't its own (it's held there, so it
    /// shows in that display's strip).
    func holdApp(_ window: ForeignWindow, onto: NSScreen? = nil) {
        if sides.park(window, makeRoom: false, onto: onto) { return }
        let desktop = onto.map { Desktops.active(on: $0.displayID) }
            ?? Desktops.of(window.element).first ?? Desktops.active(on: state.notchScreen?.displayID)
        // Held on the sides counts too: 6 per desktop in all.
        guard state.dock.apps(on: desktop).count < NotchDock.maxApps else { return NSSound.beep() }
        let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "App"
        let app = HeldApp(pid: window.pid, appName: name, desktop: desktop)
        minimized[app.id] = window
        heldAt[app.id] = Date()
        windows.setMinimized(true, window)
        state.updateDock { $0.apps.append(app) }
        log.debug("hold: \(name, privacy: .public) on desktop \(app.desktop ?? -1), showing \(self.state.dock.desktop ?? -1), \(self.state.dock.shownApps.count) shown")
    }

    func setKeep(_ mode: KeepMode) {
        state.updateDock { $0.keep = mode }
    }

    func toggleKeep() {
        state.updateDock { $0.keep = $0.keep.next }
    }

    /// Clicking the tab that's showing folds its content away (Today, Finder or Monitor: none showing); clicking
    /// it again, or another tab, brings it back.
    func select(_ tab: PanelTab) {
        let folding = tab == state.dock.tab && !state.dock.contentHidden
        state.updateDock { $0.tab = tab; $0.contentHidden = folding }
        if tab == .finder { show(shown) }
    }

    // MARK: Giving windows back

    /// Clicked in the tab: the window comes back where it was, on the current desktop (minimized windows
    /// belong to no desktop, so they open on whichever one is showing).
    /// Clicked: it leaves the strip and fills the desktop in front, the windows already here left where they are.
    /// Option-click swaps it with the app in front instead, like Stage Manager, setting that one aside in its place.
    /// With Quick Dock on, every click swaps: one window at a time, so the one in front goes to the strip.
    /// One held on a side is let go of and fills the desktop (with Quick Dock, swapping with the window in front);
    /// its card on the edge is what pops it out to use from the side.
    func restore(_ app: HeldApp) {
        if app.onSide {
            state.send(.dismiss)
            guard let window = sides.window(app.id) else { return }
            if state.settings.quickDock { return restoreSide(window) }
            sides.unpark(window)
            ignoreActivationUntil = Date().addingTimeInterval(0.8)
            fill(window)
            windows.raise(window, activate: true)
            return
        }
        let swap = state.settings.quickDock || NSEvent.modifierFlags.contains(.option)
        let front = swap ? frontWindowToSetAside(other: app.pid) : nil
        guard let window = take(app) else { return }
        windows.setMinimized(false, window)
        if let front { holdApp(front) }
        // Centre stage once it has landed: in front and focused, like Stage Manager, and on screen: filling the
        // desktop with Quick Dock, otherwise centred if any of it was off the screen. Safe now that the strip only
        // shows this desktop's windows, which come back here, so focusing can't switch desktops.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            log.debug("restore: \(Desktops.describe(window.element) ?? "desktop unknown", privacy: .public)")
            ignoreActivationUntil = Date().addingTimeInterval(0.8)
            fit(window, fill: !swap)
            windows.raise(window, activate: true)
            watchForDesktopJump()
        }
    }

    /// Quick Dock: a card clicked on the side swaps with the window in front, filling the desktop while that one
    /// goes to the side.
    func restoreSide(_ window: ForeignWindow) {
        let front = frontWindowToSetAside(other: window.pid)
        guard sides.unpark(window) != nil else { return }
        ignoreActivationUntil = Date().addingTimeInterval(0.8)
        fill(window)
        windows.raise(window, activate: true)
        if let front { holdApp(front) }
    }

    // MARK: Quick Dock

    /// Fills the desktop with Quick Dock (or `fill`); otherwise only pulls back a window that's partly off its
    /// screen, centred, shrunk to fit if needed.
    private func fit(_ window: ForeignWindow, fill: Bool = false) {
        guard let frame = windows.frame(of: window),
              let screen = NSScreen.screens.max(by: { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area })
        else { return }
        let area = screen.visibleFrame
        if fill || state.settings.quickDock {
            windows.setFrame(area, of: window)
        } else if !area.contains(frame) {
            let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
            windows.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                    width: size.width, height: size.height), of: window)
        }
    }

    /// Fills its screen's desktop (minus menu bar and Dock).
    func fill(_ window: ForeignWindow) {
        sides.unpark(window)
        fit(window, fill: true)
    }

    /// Quick Dock setting a window aside: like `holdApp`, but a full strip makes room. It holds 6 per desktop;
    /// past that the oldest stays minimized in the Dock and leaves the strip.
    func setAside(_ window: ForeignWindow) {
        if sides.isParked(window) || sides.park(window, makeRoom: true) { return }
        let desktop = Desktops.of(window.element).first
        // Full (sides and strip together): the oldest in the strip makes room.
        let held = state.dock.apps(on: desktop)
        if held.count >= NotchDock.maxApps, let oldest = held.first(where: { !$0.onSide }) {
            minimized[oldest.id] = nil
            heldAt[oldest.id] = nil
            state.updateDock { dock in dock.apps.removeAll { $0.id == oldest.id } }
        }
        holdApp(window)
    }

    /// The window in front on this desktop, if it's an ordinary window of another app that can be set aside.
    private func frontWindowToSetAside(other pid: Int32) -> ForeignWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != pid,
              app.processIdentifier != getpid(), app.bundleIdentifier != FinderFolder.bundleID || hasFinderWindow(app),
              let window = windows.frontWindow(pid: app.processIdentifier), AXWindowControl.isStandard(window),
              !windows.isMinimized(window) else { return nil }
        let here = Desktops.active(on: state.notchScreen?.displayID)
        guard here == nil || Desktops.of(window.element).contains(here!) else { return nil }
        return window
    }

    /// Finder is "in front" whenever the desktop is clicked; only a real Finder window counts.
    private func hasFinderWindow(_ app: NSRunningApplication) -> Bool {
        windows.frontWindow(pid: app.processIdentifier).map(AXWindowControl.isStandard) ?? false
    }

    /// Logs if focusing a restored window still switched desktops, to know whether this needs more.
    private func watchForDesktopJump() {
        let center = NSWorkspace.shared.notificationCenter
        if let jumpWatch { center.removeObserver(jumpWatch) }
        jumpWatch = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                       queue: .main) { _ in log.debug("restore: desktop switched after restoring") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let watch = jumpWatch else { return }
            center.removeObserver(watch)
            jumpWatch = nil
        }
    }

    /// Dragged out of the tab or the dropdown: the icon leaves and lifts into the pointer while the window is
    /// restored, exactly as the Dock would (minimized windows come back on the desktop you're on); then it's moved
    /// under the pointer, the icon swells into it, and it follows the pointer until the button comes up, as if it
    /// had been picked up by its title bar. (An earlier version hid the app around the restore to skip the Dock's
    /// animation; showing the app again sent the window back to the desktop it came from.)
    func pullOut(_ app: HeldApp, icon: NSImage) {
        if app.onSide { return pullOutSide(app, icon: icon) }
        guard follower == nil, let window = take(app), let size = windows.frame(of: window)?.size else { return }
        let start = NSEvent.mouseLocation
        // From the dropdown, it closes out of the way; from the tab, the notch is closed already.
        state.send(.dismiss)
        ghost.lift(icon, at: start)
        windows.setFrame(Self.hanging(size, from: start), of: window)
        windows.setMinimized(false, window)
        pulled = (window, size)
        follower = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        // Once it has had a moment to come back: show it, and turn the icon into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let frame = Self.hanging(size, from: NSEvent.mouseLocation)
            windows.setFrame(frame, of: window)
            log.debug("pull out: \(Desktops.describe(window.element) ?? "desktop unknown", privacy: .public)")
            // Only brought to the front while it's in your hand; the app is activated once it's let go.
            windows.raise(window, activate: false)
            ghost.become(frame)
        }
    }

    /// One held on a side, dragged out: let go of, and straight into the pointer like a minimized one (it's
    /// already a window on screen, so there's no wait for it to come back).
    private func pullOutSide(_ app: HeldApp, icon: NSImage) {
        guard follower == nil, let window = sides.window(app.id), let size = windows.frame(of: window)?.size else { return }
        sides.unpark(window)
        let start = NSEvent.mouseLocation
        state.send(.dismiss)
        ghost.lift(icon, at: start)
        let frame = Self.hanging(size, from: start)
        windows.setFrame(frame, of: window)
        windows.raise(window, activate: false)
        ghost.become(frame)
        pulled = (window, size)
        follower = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    private func follow() {
        guard let pulled else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            follower?.invalidate()
            follower = nil
            self.pulled = nil
            // Let go: in front and focused.
            windows.raise(pulled.window, activate: true)
            watchForDesktopJump()
            return
        }
        windows.setFrame(Self.hanging(pulled.size, from: NSEvent.mouseLocation), of: pulled.window)
    }

    /// "Let Go" on an icon: Jarvis stops holding it and the window comes back as it was (a side's to where it
    /// was before; a minimized one un-minimized, on screen), without filling the desktop.
    func letGo(_ app: HeldApp) {
        if app.onSide { return sides.letGo(app.id) }
        guard let window = take(app) else { return }
        windows.setMinimized(false, window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fit(window)
            self?.windows.raise(window, activate: true)
        }
    }

    /// Lets go of a held app; nil when its window was closed meanwhile (its app is brought forward instead).
    private func take(_ app: HeldApp) -> ForeignWindow? {
        state.updateDock { $0.apps.removeAll { $0.id == app.id } }
        guard let window = minimized.removeValue(forKey: app.id), windows.frame(of: window) != nil else {
            NSRunningApplication(processIdentifier: app.pid)?.activate()
            return nil
        }
        return window
    }

    /// Opens the shown folder in a Finder window on the current desktop, top edge at `point`.
    func releaseFolder(at point: CGPoint) {
        NSWorkspace.shared.open(shown)
        // Finder takes a moment to make the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [windows] in
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: FinderFolder.bundleID).first,
                  let window = windows.frontWindow(pid: finder.processIdentifier),
                  let frame = windows.frame(of: window) else { return }
            windows.setFrame(Self.hanging(frame.size, from: point), of: window)
        }
        if !state.notch.locked { state.send(.dismiss) }
    }

    /// A window of `size` hanging from `point` by the middle of its title bar, kept below the menu bar.
    private static func hanging(_ size: CGSize, from point: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
        let top = min(point.y + 12, screen?.visibleFrame.maxY ?? point.y)
        return CGRect(x: point.x - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    // MARK: The Finder tab

    /// Shows a folder and keeps it up to date while it changes on disk.
    func show(_ folder: URL) {
        shown = folder
        items = FolderShelf.list(folder)
        watcher?.cancel()
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            log.debug("finder: can't watch \(folder.path, privacy: .public) (errno \(errno))")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                log.debug("finder: folder changed")
                self.items = FolderShelf.list(self.shown)
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    var canGoUp: Bool { shown.pathComponents.count > 1 }

    func showParent() {
        guard canGoUp else { return }
        show(shown.deletingLastPathComponent())
    }

    /// Files dropped on the folder; Option copies instead of moving.
    func drop(_ urls: [URL]) -> Bool {
        log.debug("finder: \(urls.count) dropped in")
        let moved = FolderShelf.drop(urls, into: shown, copy: NSEvent.modifierFlags.contains(.option))
        items = FolderShelf.list(shown)
        return !moved.isEmpty
    }

    func open(_ item: ShelfItem) {
        if item.isFolder {
            show(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func fileDragMoved(_ point: CGPoint) {
        onFileDrag(point)
    }

    /// The file landed (or the drag was cancelled): whatever happened on disk, show it now rather than wait
    /// for the folder's change notice.
    func fileDragEnded() {
        onFileDrag(nil)
        items = FolderShelf.list(shown)
    }

    // MARK: Dragging the folder out of the notch

    /// The folder's title being dragged: a ghost follows the pointer once it's off the notch.
    func dragOut(icon: NSImage) {
        let point = NSEvent.mouseLocation
        ghost.show(icon, at: point, visible: !isOverOpenNotch(point))
    }

    /// Let go off the notch: `release` gets the drop point. Let go on it: nothing happens.
    func endDragOut(_ release: (CGPoint) -> Void) {
        ghost.hide()
        let point = NSEvent.mouseLocation
        guard !isOverOpenNotch(point) else { return }
        release(point)
    }

    private func isOverOpenNotch(_ point: CGPoint) -> Bool {
        state.layout.hotZone(for: .open).contains(point)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
