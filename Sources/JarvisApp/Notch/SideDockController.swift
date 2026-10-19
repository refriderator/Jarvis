import AppKit
import JarvisKit
import os

private let log = Logger(subsystem: "jarvis.dock", category: "sides")

/// A window held on the side of its display: slid off the edge (see `SideDock`), still on its own desktop.
struct ParkedWindow: Identifiable {
    let id = UUID()
    let window: ForeignWindow
    /// Where it was before it was held, to give it back there (moved with its display when displays are rearranged).
    var original: CGRect
    var side: ScreenSide
    var display: CGDirectDisplayID?
    var desktop: Int?
    var parkedAt: CGRect
    /// The size it had when it last went back from being popped out (resized there or not), to pop out at again.
    var popSize: CGSize?
}

/// Holding windows on the sides of the screen, like Stage Manager's strip but with the real windows waiting
/// just off the left and right edges. Hover an edge and cards for that side's windows slide out (`SidePeek`).
///
/// Clicking a card with Quick Dock on swaps its window with the one in front (`onPick`). With it off, the window
/// pops out a little way from its edge, over the one in front, to be used right there; once the pointer leaves
/// it, it slides back to the side and the keyboard goes back to the app in front, which never moved.
@MainActor
final class SideDockController {
    private(set) var parked: [ParkedWindow] = [] {
        didSet { onChange(parked) }
    }
    /// Swaps a picked window with the one in front (Quick Dock); set by `DockController`.
    var onPick: (ForeignWindow) -> Void = { _ in }
    /// The held windows changed, so the notch's strip can show them too; set by `DockController`.
    var onChange: ([ParkedWindow]) -> Void = { _ in }
    /// Windows minimized into the notch's strip on a desktop: they share its `SideDock.maxWindows`.
    var minimizedOn: (Int?) -> Int = { _ in 0 }

    private let state: AppState
    private let windows: WindowControlling
    private let peek: SidePeek
    private var tracker: Timer?
    /// Ticks of `tracker`, so held windows are checked (`prune`) only every so often.
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    /// The cards showing: which display and side.
    private var showing: (display: CGDirectDisplayID?, side: ScreenSide)?
    /// The card under the pointer.
    private var hovered: UUID?
    /// The window popped out, the app that was in front, and whether the pointer has been on it yet.
    private var popped: (id: UUID, frame: CGRect, previous: NSRunningApplication?, entered: Bool)?
    /// Popped by picking it in Mission Control: where the pointer was then. Moving away from there (not onto the
    /// window) sends it back, like a peek; it was never under the pointer, so it otherwise stayed out for good.
    private var poppedFrom: CGPoint?
    /// Mission Control is showing, or when it last closed: a window picked there comes forward just after.
    private var missionControlShowing = false
    private var missionControlClosedAt: Date?
    private var leftAt: Date?
    /// When another app came forward without you picking it: the popped window closed or an app quit (macOS
    /// picks one), or it went back to the side and the app before it got the keyboard back. That app's held window
    /// mustn't pop out as if you'd ⌘-Tabbed to it.
    private var notPickedAt: Date?
    private var sliding: Timer?
    /// A card being dragged, and where it would land now.
    private var dragging: UUID?
    private var dropAt: (display: CGDirectDisplayID?, side: ScreenSide, index: Int)?
    /// ...or, dragged into the middle of a display, where its window goes when it's let go of there.
    private var releaseAt: CGRect?
    /// Where the popped window was when the button went down on it, and whether that press was on its title bar,
    /// to tell a title-bar drag from a click or a resize.
    private var poppedPress: (frame: CGRect, onTitleBar: Bool)?
    private lazy var outline = ReleaseOutline(skin: { [state] in state.skin })
    /// Where a window last waited: so that coming back to the side (a Quick Dock swap, say) it goes to the same side
    /// and place, and windows keep their side and the cards their order.
    private struct Home {
        let window: ForeignWindow
        let display: CGDirectDisplayID?
        let desktop: Int?
        let side: ScreenSide
        /// Its place among that side's cards.
        let place: Int
    }
    private var homes: [Home] = []
    /// The window being slid, from where to where, since when, and what to do once it's there.
    private var slide: (window: ForeignWindow, start: CGRect, target: CGRect, began: Date, done: (CGRect?) -> Void)?
    /// Each display's frame as last seen, so held windows can follow their display when displays are rearranged.
    private var displayFrames = SideDockController.currentDisplayFrames()
    /// Displays just changed: until held windows are back off their sides, ones macOS moved aren't forgotten (`prune`).
    private var rearranging = false
    /// When strays were last looked for (`rescueStrays`): changing desktops looks again, but not every swipe.
    private var rescuedAt: Date?

    init(state: AppState, windows: WindowControlling) {
        self.state = state
        self.windows = windows
        peek = SidePeek(state: state)
        peek.onPick = { [weak self] id in self?.pick(id) }
        peek.onDrag = { [weak self] id in self?.beginDrag(id) }
        peek.onLetGo = { [weak self] id in self?.letGo(id) }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hideCards()
                // A desktop's windows can only be seen while it's showing, so ones stranded there are found now.
                if let self, self.rescuedAt.map({ Date().timeIntervalSince($0) > 5 }) ?? true { self.rescueStrays() }
            }
        })
        // Waking, macOS can move windows that are off every edge while the displays come back (and an app slow to
        // answer just after waking can miss being put back): held ones go back off their sides, others come back.
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displaysChanged() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.activated(pid) }
        })
        // An app can take a while to quit after its last window closes; macOS then brings another one forward.
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notPickedAt = Date() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.displaysChanged() } })
        // Windows a Jarvis that was killed or crashed left off the edge (a normal quit puts them back).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.rescueStrays() }
    }

    // MARK: Holding

    func isParked(_ window: ForeignWindow) -> Bool { parked.contains { $0.window == window } }
    func window(_ id: UUID) -> ForeignWindow? { parked.first { $0.id == id }?.window }
    func isPopped(_ window: ForeignWindow) -> Bool { popped.map { id in parked.first { $0.id == id.id }?.window == window } ?? false }

    /// Slides a window off `side` of its display (if free), or the nearer free one. `onto` another display (it was
    /// put in the notch, or a tray, there), it goes to that display's side instead, as if it had been at the same
    /// place relative to that display's middle; letting go still puts it back where it really was. False when it
    /// can't be held there (another display on both sides, or this desktop already holds `SideDock.maxWindows`
    /// and `makeRoom` is off).
    @discardableResult
    func park(_ window: ForeignWindow, makeRoom: Bool, side wanted: ScreenSide? = nil, onto: NSScreen? = nil) -> Bool {
        guard !isParked(window) else { return true }
        guard let original = windows.frame(of: window), let from = Self.screen(for: original) else { return false }
        let screen = onto ?? from
        let moving = screen != from
        let frame = moving ? original.offsetBy(dx: screen.frame.midX - from.frame.midX, dy: screen.frame.midY - from.frame.midY)
                           : original
        let free = SideDock.freeSides(of: screen.frame, others: NSScreen.screens.map(\.frame))
        // Moved to another display, it joins the desktop showing there.
        let desktop = (moving ? nil : Desktops.of(window.element).first) ?? Desktops.active(on: screen.displayID)
        homes.removeAll { windows.frame(of: $0.window) == nil }
        // Back where it waited last, if that's on this display and desktop.
        let home = homes.first { $0.window == window && $0.display == screen.displayID && $0.desktop == desktop
            && free.contains($0.side) }
        guard let side = wanted.flatMap({ free.contains($0) ? $0 : nil }) ?? home?.side
                ?? SideDock.side(for: frame, on: screen.frame, free: free) else { return false }
        let here = parked.filter { $0.desktop == desktop }
        // One limit per desktop for everything held, on the sides or in the strip.
        if here.count + minimizedOn(desktop) >= SideDock.maxWindows {
            guard makeRoom, let oldest = here.first else { return false }
            // Past a full side, the oldest goes back where it was and is minimized in the Dock.
            unpark(oldest.window)
            windows.setMinimized(true, oldest.window)
        }
        let target = SideDock.parked(frame, side: side, screen: screen.frame, visible: screen.visibleFrame, others: Self.otherScreens(screen))
        let got = windows.setFrame(target, of: window) ?? target
        let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "?"
        log.debug("park: \(name, privacy: .public) on the \(side.rawValue, privacy: .public), got x \(got.minX) for \(target.minX)")
        let item = ParkedWindow(window: window, original: original, side: side, display: screen.displayID,
                                desktop: desktop, parkedAt: got)
        // Before the card now at its old place on that side, or after the side's last.
        let onSide = cards(display: item.display, side: side, desktop: desktop)
        let place = home?.side == side ? home?.place ?? onSide.count : onSide.count
        let at = place < onSide.count ? onSide[place] : (onSide.last.map { $0 + 1 } ?? parked.endIndex)
        parked.insert(item, at: at)
        startTracking()
        return true
    }

    /// Indices in `parked` of the cards on one side of a display's desktop, in order.
    private func cards(display: CGDirectDisplayID?, side: ScreenSide, desktop: Int?) -> [Int] {
        parked.indices.filter { parked[$0].display == display && parked[$0].side == side && parked[$0].desktop == desktop }
    }

    /// Lets go of a held window without moving it; returns where it was before it was held.
    @discardableResult
    func unpark(_ window: ForeignWindow) -> CGRect? {
        guard let index = parked.firstIndex(where: { $0.window == window }) else { return nil }
        let leaving = parked[index]
        let place = cards(display: leaving.display, side: leaving.side, desktop: leaving.desktop).firstIndex(of: index) ?? 0
        let item = parked.remove(at: index)
        homes.removeAll { $0.window == window }
        homes.append(Home(window: window, display: item.display, desktop: item.desktop, side: item.side, place: place))
        if popped?.id == item.id { popped = nil }
        if parked.isEmpty { hideCards() }
        return item.original
    }

    /// No longer held (the card's or the notch icon's "Let go"): back where it was before, in front and focused.
    func letGo(_ id: UUID) {
        guard let item = parked.first(where: { $0.id == id }) else { return }
        sliding?.invalidate()
        sliding = nil
        slide = nil
        unpark(item.window)
        windows.setFrame(item.original, of: item.window)
        windows.raise(item.window, activate: true)
    }

    /// Every held window back where it was, on quitting.
    func releaseAll() {
        for item in parked where windows.frame(of: item.window) != nil {
            windows.setFrame(item.original, of: item.window)
        }
        parked = []
        popped = nil
        hideCards()
    }

    // MARK: The pointer

    private func startTracking() {
        guard tracker == nil else { return }
        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
    }

    private func track() {
        // Asking every held window where it is goes to each app (Accessibility) and waits for it, on the main
        // thread: 30 times a second, a busy app made the cards stutter as they slid out. Twice a second is plenty to
        // notice one brought back another way, and not while the cards are out or being dragged.
        ticks += 1
        if ticks % 15 == 0, showing == nil, dragging == nil { prune() }
        guard !parked.isEmpty else {
            tracker?.invalidate()
            tracker = nil
            return
        }
        let pointer = NSEvent.mouseLocation
        if dragging != nil { return trackDrag(pointer) }
        // Mission Control is above every window but the cards': out there, they'd take its clicks.
        if missionControlShowing { return }
        // Cards first: they can be out over a popped window (its edge touched again).
        if let showing { return trackCards(pointer, showing: showing) }
        if popped != nil { return trackPopped(pointer) }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
            for side in ScreenSide.allCases where SideDock.atEdge(pointer, side: side, screen: screen.frame,
                                                                  visible: screen.visibleFrame) {
                let here = waiting(on: side, of: screen)
                guard !here.isEmpty, NSEvent.pressedMouseButtons == 0 else { continue }
                showCards(here, side: side, on: screen)
                break
            }
        }
    }

    private func trackCards(_ pointer: CGPoint, showing: (display: CGDirectDisplayID?, side: ScreenSide)) {
        // Well away from the cards: they slide back. Anywhere in their column, from the edge to just past them, top
        // to bottom, they stay: only the 3 pt edge itself kept them above or below the cards, so the pointer
        // wobbling off it hid them and the next touch slid them straight back out, and they stuttered.
        let column = NSScreen.screens.first(where: { $0.displayID == showing.display }).map { screen in
            let visible = screen.visibleFrame
            let near = showing.side == .left ? screen.frame.minX : peek.area.minX - 40
            let far = showing.side == .left ? peek.area.maxX + 40 : screen.frame.maxX
            return CGRect(x: near, y: visible.minY, width: far - near, height: visible.height)
        } ?? .zero
        guard column.contains(pointer) || peek.area.insetBy(dx: -40, dy: -40).contains(pointer) else { return hideCards() }
        hovered = peek.card(at: pointer)?.id
        peek.highlight(hovered)
    }

    /// Slides back as soon as the pointer, having been on the popped window, leaves it (not while a button is
    /// down, so dragging something out of it works).
    private func trackPopped(_ pointer: CGPoint) {
        guard var current = popped else { return }
        // Its real edges, once it's out: resized there (or by the app), "on it" follows them.
        if sliding == nil, let item = parked.first(where: { $0.id == current.id }),
           let now = windows.frame(of: item.window), now != current.frame {
            current.frame = now
            popped?.frame = now
        }
        if trackPoppedDrag(pointer, frame: current.frame) { return }
        // The edge it came out of stays free (it sits `SideDock.popInset` in): touching it sends the window back to
        // its place and brings the cards out instead.
        if NSEvent.pressedMouseButtons == 0, let item = parked.first(where: { $0.id == current.id }),
           let screen = NSScreen.screens.first(where: { $0.displayID == item.display }),
           SideDock.atEdge(pointer, side: item.side, screen: screen.frame, visible: screen.visibleFrame) {
            retract(giveBackFocus: true)
            return showCards(waiting(on: item.side, of: screen), side: item.side, on: screen)
        }
        if current.frame.insetBy(dx: -SideDock.leaveMargin, dy: -SideDock.leaveMargin).contains(pointer) {
            popped?.entered = true
            poppedFrom = nil
            leftAt = nil
            return
        }
        if let from = poppedFrom, NSEvent.pressedMouseButtons == 0, hypot(pointer.x - from.x, pointer.y - from.y) > 8 {
            return retract(giveBackFocus: true)
        }
        guard current.entered, NSEvent.pressedMouseButtons == 0 else { return }
        // A moment's grace, so brushing past its edge doesn't send it back.
        if let leftAt, Date().timeIntervalSince(leftAt) > SideDock.leaveGrace {
            retract(giveBackFocus: true)
        } else if leftAt == nil {
            leftAt = Date()
        }
    }

    /// The popped window dragged by its title bar: in the middle of a display the outline shows, and let go
    /// there it's no longer held, like a card dropped there. True when it was let go of (it's not popped any more).
    private func trackPoppedDrag(_ pointer: CGPoint, frame: CGRect) -> Bool {
        guard let current = popped, let item = parked.first(where: { $0.id == current.id }) else { return false }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            poppedPress = nil
            guard let target = releaseAt else { return false }
            release(item, to: target)
            return true
        }
        if poppedPress == nil {
            poppedPress = (frame, pointer.y >= frame.maxY - DockController.titleBarDepth && frame.contains(pointer))
        }
        // Only once the window itself is moving, by its title bar: a press inside it (a click, a text selection)
        // isn't a drag, and neither is dragging an edge (a resize moves the origin too, but changes the size).
        guard let press = poppedPress, press.onTitleBar,
              press.frame.origin != frame.origin, press.frame.size == frame.size,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              SideDock.inMiddle(pointer, screen: screen.frame) else {
            releaseAt = nil
            outline.hide()
            return false
        }
        let target = SideDock.released(frame.size, visible: screen.visibleFrame)
        releaseAt = target
        outline.show(target)
        return false
    }

    /// No longer held: put where the outline was, in front.
    private func release(_ item: ParkedWindow, to frame: CGRect) {
        releaseAt = nil
        outline.hide()
        if popped?.id == item.id { popped = nil }
        unpark(item.window)
        windows.setFrame(frame, of: item.window)
        windows.raise(item.window, activate: true)
    }

    // MARK: Cards

    /// The held windows waiting on `side` of `screen`, on the desktop it's showing.
    private func waiting(on side: ScreenSide, of screen: NSScreen) -> [ParkedWindow] {
        let desktop = Desktops.active(on: screen.displayID)
        return parked.filter { $0.side == side && $0.display == screen.displayID
            && ($0.desktop == nil || desktop == nil || $0.desktop == desktop) }
    }

    private func showCards(_ items: [ParkedWindow], side: ScreenSide, on screen: NSScreen) {
        showing = (screen.displayID, side)
        hovered = nil
        peek.show(items, side: side, on: screen)
    }

    private func hideCards() {
        guard showing != nil else { return }
        showing = nil
        hovered = nil
        peek.hide()
    }

    // MARK: Dragging cards

    /// A card dragged: it lifts into the pointer, and its slot shows where it would land.
    private func beginDrag(_ id: UUID) {
        guard dragging == nil, parked.contains(where: { $0.id == id }) else { return }
        dragging = id
        dropAt = nil
        peek.lift(id)
        trackDrag(NSEvent.mouseLocation)
    }

    /// While it's dragged, the cards of the side under the pointer (on any display) show with its slot among them;
    /// let go, it moves there.
    private func trackDrag(_ pointer: CGPoint) {
        guard let id = dragging else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return endDrag() }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              let item = parked.first(where: { $0.id == id }) else { return }
        // In the middle: an outline where its window goes if it's let go of here, and no cards.
        if SideDock.inMiddle(pointer, screen: screen.frame) {
            let size = windows.frame(of: item.window)?.size ?? item.original.size
            let frame = SideDock.released(size, visible: screen.visibleFrame)
            releaseAt = frame
            dropAt = nil
            outline.show(frame)
            if showing != nil {
                showing = nil
                peek.hide()
            }
            return
        }
        releaseAt = nil
        outline.hide()
        let free = SideDock.freeSides(of: screen.frame, others: NSScreen.screens.map(\.frame))
        let others = { (side: ScreenSide) in self.waiting(on: side, of: screen).filter { $0.id != id } }
        guard let target = SideDock.cardDrop(pointer, screen: screen.frame, visible: screen.visibleFrame,
                                             free: free, count: { others($0).count }) else { return }
        let next = (screen.displayID, target.side, target.index)
        if let dropAt, dropAt == next { return }
        let sameSide = dropAt.map { $0.display == next.0 && $0.side == next.1 } ?? (item.display == next.0 && item.side == next.1)
        dropAt = next
        var cards = others(target.side)
        cards.insert(item, at: target.index)
        showing = (screen.displayID, target.side)
        peek.show(cards, side: target.side, on: screen, placeholder: id, animated: !sameSide)
    }

    private func endDrag() {
        guard let id = dragging else { return }
        dragging = nil
        peek.dropGhost()
        outline.hide()
        if let frame = releaseAt, let item = parked.first(where: { $0.id == id }) {
            // Let go of in the middle.
            return release(item, to: frame)
        }
        defer { dropAt = nil }
        guard let dropAt, let screen = NSScreen.screens.first(where: { $0.displayID == dropAt.display }),
              let from = parked.firstIndex(where: { $0.id == id }) else { return hideCards() }
        var item = parked.remove(at: from)
        let moved = item.display != dropAt.display || item.side != dropAt.side
        if moved {
            if popped?.id == id { popped = nil }
            let size = windows.frame(of: item.window)?.size ?? item.original.size
            let target = SideDock.parked(CGRect(origin: item.parkedAt.origin, size: size), side: dropAt.side,
                                         screen: screen.frame, visible: screen.visibleFrame, others: Self.otherScreens(screen))
            // The desktop it's going to, read first: a window off the edge can count as another display's after.
            item.desktop = item.display == screen.displayID ? Desktops.of(item.window.element).first : nil
            item.desktop = item.desktop ?? Desktops.active(on: screen.displayID)
            item.parkedAt = windows.setFrame(target, of: item.window) ?? target
            item.side = dropAt.side
            item.display = screen.displayID
            log.debug("drag: to the \(dropAt.side.rawValue, privacy: .public), got x \(item.parkedAt.minX)")
        }
        // In `parked`, before the card it was dropped above on that side (or after the side's last one).
        let side = parked.indices.filter { parked[$0].display == item.display && parked[$0].side == item.side
            && (parked[$0].desktop == nil || item.desktop == nil || parked[$0].desktop == item.desktop) }
        let at = dropAt.index < side.count ? side[dropAt.index] : (side.last.map { $0 + 1 } ?? parked.endIndex)
        parked.insert(item, at: at)
        // The cards stay out where it landed, as they are now.
        showing = (screen.displayID, item.side)
        peek.show(waiting(on: item.side, of: screen), side: item.side, on: screen, animated: false)
    }

    /// A card (or its icon in the notch) clicked.
    func pick(_ id: UUID) {
        guard let item = parked.first(where: { $0.id == id }) else { return }
        hideCards()
        if state.settings.quickDock {
            onPick(item.window)
        } else {
            pop(id)
        }
    }

    // MARK: Using a held window from the side

    /// Pops a held window out over the one in front, in front and focused.
    func pop(_ id: UUID) {
        poppedFrom = nil
        guard let item = parked.first(where: { $0.id == id }),
              let screen = NSScreen.screens.first(where: { $0.displayID == item.display }) else { return }
        if popped != nil, popped?.id != id { retract(giveBackFocus: false) }
        hideCards()
        let front = NSWorkspace.shared.frontmostApplication
        let previous = front?.processIdentifier == item.window.pid || front?.processIdentifier == getpid() ? popped?.previous : front
        let frame = SideDock.popped(item.popSize, side: item.side, visible: screen.visibleFrame)
        popped = (id, frame, previous, frame.contains(NSEvent.mouseLocation))
        leftAt = nil
        log.debug("pop: \(NSRunningApplication(processIdentifier: item.window.pid)?.localizedName ?? "?", privacy: .public)")
        windows.raise(item.window, activate: true)
        slide(item.window, to: frame) { [weak self] got in
            guard let self, var got, popped?.id == id else { return }
            // Apps keep their own minimum size: one that came out bigger than asked is moved fully on screen.
            if !screen.visibleFrame.contains(got) {
                let fixed = SideDock.onScreen(got, side: item.side, visible: screen.visibleFrame)
                got = windows.setFrame(fixed, of: item.window) ?? fixed
            }
            popped?.frame = got
        }
    }

    /// Sends the popped window back to its side; with `giveBackFocus`, the app that was in front gets the
    /// keyboard back.
    private func retract(giveBackFocus: Bool) {
        poppedFrom = nil
        guard let current = popped, let item = parked.first(where: { $0.id == current.id }) else {
            popped = nil
            return
        }
        popped = nil
        leftAt = nil
        log.debug("retract: \(NSRunningApplication(processIdentifier: item.window.pid)?.localizedName ?? "?", privacy: .public)")
        if giveBackFocus, let previous = current.previous, !previous.isTerminated {
            notPickedAt = Date()
            previous.activate()
        }
        // It keeps the size it has now: out next time at this size, and parked at it (off the edge as before).
        var target = item.parkedAt
        if let size = windows.frame(of: item.window)?.size,
           let screen = NSScreen.screens.first(where: { $0.displayID == item.display }),
           let index = parked.firstIndex(where: { $0.id == item.id }) {
            target = SideDock.parked(CGRect(origin: item.parkedAt.origin, size: size), side: item.side,
                                     screen: screen.frame, visible: screen.visibleFrame, others: Self.otherScreens(screen))
            parked[index].popSize = size
            parked[index].parkedAt = target
        }
        slide(item.window, to: target) { _ in }
    }

    /// Another app came forward (⌘-Tab, a click): another app sends a popped window back without taking the
    /// keyboard away from it. With Quick Dock off, a held window's app (⌘-Tab to it) pops it out; with it on,
    /// Quick Dock swaps it in instead.
    private func activated(_ pid: Int32?) {
        guard let pid, pid != getpid() else { return }
        if let current = popped {
            let item = parked.first(where: { $0.id == current.id })
            if item.flatMap({ windows.frame(of: $0.window) }) == nil {
                // The popped window just closed (or its app quit): this app came forward on its own.
                poppedGone()
                return
            }
            if let item, item.window.pid != pid { retract(giveBackFocus: false) }
        }
        guard !state.settings.quickDock, !notPicked else { return }
        // A moment for the app to bring its window forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !notPicked, let front = windows.frontWindow(pid: pid),
                  let item = parked.first(where: { $0.window == front }), popped?.id != item.id else { return }
            let fromMissionControl = missionControlShowing
                || missionControlClosedAt.map { Date().timeIntervalSince($0) < 1.5 } ?? false
            pop(item.id)
            if fromMissionControl, popped?.entered == false { poppedFrom = NSEvent.mouseLocation }
        }
    }

    /// Mission Control opened or closed (`MissionControlWatch`, through `NotchController`).
    func missionControl(showing: Bool) {
        missionControlShowing = showing
        if showing { hideCards() } else { missionControlClosedAt = Date() }
    }

    private func poppedGone() {
        popped = nil
        leftAt = nil
        notPickedAt = Date()
    }

    private var notPicked: Bool { notPickedAt.map { Date().timeIntervalSince($0) < 1 } ?? false }

    // MARK: Moving windows

    /// Moves a window to `target` over a fifth of a second, easing out (sized first, so only its position animates).
    private func slide(_ window: ForeignWindow, to target: CGRect, done: @escaping (CGRect?) -> Void) {
        sliding?.invalidate()
        sliding = nil
        guard let start = windows.frame(of: window) else { return done(nil) }
        windows.setFrame(CGRect(origin: start.origin, size: target.size), of: window)
        slide = (window, start, target, Date(), done)
        sliding = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.slideStep() }
        }
    }

    private func slideStep() {
        guard let move = slide else {
            sliding?.invalidate()
            sliding = nil
            return
        }
        let t = min(1, Date().timeIntervalSince(move.began) / 0.2)
        let eased = 1 - pow(1 - t, 3)
        let origin = CGPoint(x: move.start.minX + (move.target.minX - move.start.minX) * eased,
                             y: move.start.minY + (move.target.minY - move.start.minY) * eased)
        let got = windows.setFrame(CGRect(origin: origin, size: move.target.size), of: move.window)
        guard t >= 1 else { return }
        sliding?.invalidate()
        sliding = nil
        slide = nil
        move.done(got)
    }

    /// Forgets windows that closed, or that were moved back onto the screen some other way.
    private func prune() {
        guard !rearranging else { return }
        let screens = NSScreen.screens.map(\.frame)
        var nudged: [ParkedWindow] = []
        let gone = parked.filter { item in
            guard let frame = windows.frame(of: item.window) else { return true }
            guard popped?.id != item.id, sliding == nil else { return false }
            guard abs(frame.minX - item.parkedAt.minX) > 40 else { return false }
            // Moved, but still off the edge: macOS nudged it (the displays sleeping, say). Forgotten, it was lost
            // off the screen until its app was hidden and shown again; it goes back where it waits instead.
            if SideDock.isStranded(frame, screens: screens) {
                nudged.append(item)
                return false
            }
            log.debug("prune: a held window came back another way")
            return true
        }
        for item in nudged {
            log.debug("prune: a held window was nudged; holding it again")
            windows.setFrame(item.parkedAt, of: item.window)
        }
        // Only touched when something went: any change to `parked` updates the notch's strip, and this runs 30
        // times a second.
        guard !gone.isEmpty else { return }
        if let id = popped?.id, gone.contains(where: { $0.id == id }) { poppedGone() }
        parked.removeAll { item in gone.contains { $0.id == item.id } }
    }

    // MARK: Displays

    /// Displays were rearranged, plugged in or out, or changed size. macOS moves windows with their display, but
    /// snaps one that's off every edge to wherever it likes, so each held window is put back off its side at the
    /// display's new place, after a moment for macOS to finish. One whose display is gone, or whose side now touches
    /// another display (it would show there), is let go, back where it was.
    private func displaysChanged() {
        rearranging = true
        hideCards()
        sliding?.invalidate()
        sliding = nil
        slide = nil
        popped = nil
        poppedFrom = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.followDisplays() }
    }

    private func followDisplays() {
        let before = displayFrames
        displayFrames = Self.currentDisplayFrames()
        let all = NSScreen.screens.map(\.frame)
        for item in parked {
            guard let index = parked.firstIndex(where: { $0.id == item.id }) else { continue }
            let screen = NSScreen.screens.first { $0.displayID != nil && $0.displayID == item.display }
            var original = item.original
            var parkedAt = item.parkedAt
            if let screen, let id = item.display, let was = before[id] {
                let dx = screen.frame.minX - was.minX, dy = screen.frame.minY - was.minY
                original = original.offsetBy(dx: dx, dy: dy)
                parkedAt = parkedAt.offsetBy(dx: dx, dy: dy)
            }
            guard let screen, SideDock.freeSides(of: screen.frame, others: all).contains(item.side) else {
                unpark(item.window)
                let size = windows.frame(of: item.window)?.size ?? original.size
                let visible = all.contains { $0.intersects(original) } ? nil : (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                windows.setFrame(visible.map { SideDock.released(size, visible: $0) } ?? original, of: item.window)
                continue
            }
            let size = windows.frame(of: item.window)?.size ?? parkedAt.size
            let target = SideDock.parked(CGRect(origin: parkedAt.origin, size: size), side: item.side, screen: screen.frame,
                                         visible: screen.visibleFrame, others: Self.otherScreens(screen))
            parked[index].original = original
            parked[index].parkedAt = windows.setFrame(target, of: item.window) ?? target
        }
        rearranging = false
        // A window let go of above whose app was too slow to move it (just after waking) is still off the edge.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.rescueStrays() }
    }

    // MARK: Strays

    /// Brings back onto its display every window off an edge the way a held one waits that isn't held
    /// (`SideDock.isStranded`): centred, like one let go of in the middle. Only the desktop showing can be seen, so
    /// changing desktops looks again.
    func rescueStrays() {
        guard dragging == nil, slide == nil, !rearranging else { return }
        rescuedAt = Date()
        let screens = NSScreen.screens
        let frames = screens.map(\.frame)
        for window in windows.visibleWindows() where !isParked(window) {
            guard let frame = windows.frame(of: window), SideDock.isStranded(frame, screens: frames) else { continue }
            let near = Self.screen(for: frame).flatMap { $0.frame.intersects(frame) ? $0 : nil }
            guard let screen = near ?? NSScreen.main ?? screens.first else { continue }
            windows.setFrame(SideDock.released(frame.size, visible: screen.visibleFrame), of: window)
            log.info("brought back a window left off the edge")
        }
    }

    private static func currentDisplayFrames() -> [CGDirectDisplayID: CGRect] {
        Dictionary(NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen.frame) } },
                   uniquingKeysWith: { first, _ in first })
    }

    private static func otherScreens(_ screen: NSScreen) -> [CGRect] {
        NSScreen.screens.filter { $0 != screen }.map(\.frame)
    }

    private static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.frame.intersection(frame).size.area < b.frame.intersection(frame).size.area
        }
    }
}

private extension CGSize {
    var area: CGFloat { width * height }
}
