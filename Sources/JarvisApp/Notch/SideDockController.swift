import AppKit
import JarvisKit
import os

private let log = Logger(subsystem: "jarvis.dock", category: "sides")

/// A window held on the side of its display: slid off the edge (see `SideDock`), still on its own desktop.
struct ParkedWindow: Identifiable {
    let id = UUID()
    let window: ForeignWindow
    /// Where it was before it was held, to give it back there.
    let original: CGRect
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
    private var observers: [NSObjectProtocol] = []
    /// The cards showing: which display and side.
    private var showing: (display: CGDirectDisplayID?, side: ScreenSide)?
    /// The card under the pointer.
    private var hovered: UUID?
    /// The window popped out, the app that was in front, and whether the pointer has been on it yet.
    private var popped: (id: UUID, frame: CGRect, previous: NSRunningApplication?, entered: Bool)?
    private var leftAt: Date?
    /// When the popped window closed or its app quit. macOS then brings some other app forward by itself, which
    /// mustn't pop that app's held window out as if you'd ⌘-Tabbed to it.
    private var poppedGoneAt: Date?
    private var sliding: Timer?
    /// A card being dragged, and where it would land now.
    private var dragging: UUID?
    private var dropAt: (display: CGDirectDisplayID?, side: ScreenSide, index: Int)?
    /// ...or, dragged into the middle of a display, where its window goes when it's let go of there.
    private var releaseAt: CGRect?
    /// Where the popped window was when the button went down on it, to tell a title-bar drag from a click.
    private var poppedPress: CGPoint?
    private lazy var outline = ReleaseOutline(skin: { [state] in state.skin })
    /// The window being slid, from where to where, since when, and what to do once it's there.
    private var slide: (window: ForeignWindow, start: CGRect, target: CGRect, began: Date, done: (CGRect?) -> Void)?

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
            MainActor.assumeIsolated { self?.hideCards() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated { self?.activated(pid) }
        })
    }

    // MARK: Holding

    func isParked(_ window: ForeignWindow) -> Bool { parked.contains { $0.window == window } }
    func window(_ id: UUID) -> ForeignWindow? { parked.first { $0.id == id }?.window }
    func isPopped(_ window: ForeignWindow) -> Bool { popped.map { id in parked.first { $0.id == id.id }?.window == window } ?? false }

    /// Slides a window off `side` of its display (if free), or the nearer free one. False when it can't be held
    /// there (another display on both sides, or this desktop already holds `SideDock.maxWindows` and `makeRoom`
    /// is off).
    @discardableResult
    func park(_ window: ForeignWindow, makeRoom: Bool, side wanted: ScreenSide? = nil) -> Bool {
        guard !isParked(window) else { return true }
        guard let frame = windows.frame(of: window), let screen = Self.screen(for: frame) else { return false }
        let free = SideDock.freeSides(of: screen.frame, others: NSScreen.screens.map(\.frame))
        guard let side = wanted.flatMap({ free.contains($0) ? $0 : nil })
                ?? SideDock.side(for: frame, on: screen.frame, free: free) else { return false }
        let desktop = Desktops.of(window.element).first ?? Desktops.active(on: screen.displayID)
        let here = parked.filter { $0.desktop == desktop }
        // One limit per desktop for everything held, on the sides or in the strip.
        if here.count + minimizedOn(desktop) >= SideDock.maxWindows {
            guard makeRoom, let oldest = here.first else { return false }
            // Past a full side, the oldest goes back where it was and is minimized in the Dock.
            unpark(oldest.window)
            windows.setMinimized(true, oldest.window)
        }
        let target = SideDock.parked(frame, side: side, screen: screen.frame, visible: screen.visibleFrame)
        let got = windows.setFrame(target, of: window) ?? target
        let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "?"
        log.debug("park: \(name, privacy: .public) on the \(side.rawValue, privacy: .public), got x \(got.minX) for \(target.minX)")
        parked.append(ParkedWindow(window: window, original: frame, side: side, display: screen.displayID,
                                   desktop: desktop, parkedAt: got))
        startTracking()
        return true
    }

    /// Lets go of a held window without moving it; returns where it was before it was held.
    @discardableResult
    func unpark(_ window: ForeignWindow) -> CGRect? {
        guard let index = parked.firstIndex(where: { $0.window == window }) else { return nil }
        let item = parked.remove(at: index)
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
        prune()
        guard !parked.isEmpty else {
            tracker?.invalidate()
            tracker = nil
            return
        }
        let pointer = NSEvent.mouseLocation
        if dragging != nil { return trackDrag(pointer) }
        if popped != nil { return trackPopped(pointer) }
        if let showing {
            trackCards(pointer, showing: showing)
        } else if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) {
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
        // Well away from the cards (and the edge they came from): they slide back.
        guard peek.area.insetBy(dx: -40, dy: -40).contains(pointer) else { return hideCards() }
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
        if current.frame.insetBy(dx: -SideDock.leaveMargin, dy: -SideDock.leaveMargin).contains(pointer) {
            popped?.entered = true
            leftAt = nil
            return
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
        if poppedPress == nil { poppedPress = frame.origin }
        // Only once the window itself is moving: a press inside it (a click, a text selection) isn't a drag.
        guard poppedPress != frame.origin,
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
                                         screen: screen.frame, visible: screen.visibleFrame)
            item.parkedAt = windows.setFrame(target, of: item.window) ?? target
            item.side = dropAt.side
            item.display = screen.displayID
            item.desktop = Desktops.of(item.window.element).first ?? Desktops.active(on: screen.displayID)
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
        guard let current = popped, let item = parked.first(where: { $0.id == current.id }) else {
            popped = nil
            return
        }
        popped = nil
        leftAt = nil
        log.debug("retract: \(NSRunningApplication(processIdentifier: item.window.pid)?.localizedName ?? "?", privacy: .public)")
        if giveBackFocus, let previous = current.previous, !previous.isTerminated {
            previous.activate()
        }
        // It keeps the size it has now: out next time at this size, and parked at it (off the edge as before).
        var target = item.parkedAt
        if let size = windows.frame(of: item.window)?.size,
           let screen = NSScreen.screens.first(where: { $0.displayID == item.display }),
           let index = parked.firstIndex(where: { $0.id == item.id }) {
            target = SideDock.parked(CGRect(origin: item.parkedAt.origin, size: size), side: item.side,
                                     screen: screen.frame, visible: screen.visibleFrame)
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
        guard !state.settings.quickDock, !justLostPopped else { return }
        // A moment for the app to bring its window forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !justLostPopped, let front = windows.frontWindow(pid: pid),
                  let item = parked.first(where: { $0.window == front }), popped?.id != item.id else { return }
            pop(item.id)
        }
    }

    private func poppedGone() {
        popped = nil
        leftAt = nil
        poppedGoneAt = Date()
    }

    private var justLostPopped: Bool { poppedGoneAt.map { Date().timeIntervalSince($0) < 1 } ?? false }

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
        let gone = parked.filter { item in
            guard let frame = windows.frame(of: item.window) else { return true }
            guard popped?.id != item.id, sliding == nil else { return false }
            let back = abs(frame.minX - item.parkedAt.minX) > 40
            if back { log.debug("prune: a held window came back another way") }
            return back
        }
        // Only touched when something went: any change to `parked` updates the notch's strip, and this runs 30
        // times a second.
        guard !gone.isEmpty else { return }
        if let id = popped?.id, gone.contains(where: { $0.id == id }) { poppedGone() }
        parked.removeAll { item in gone.contains { $0.id == item.id } }
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
