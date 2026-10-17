import AppKit
import JarvisKit
import Observation
import SwiftUI
import os

private let log = Logger(subsystem: "jarvis.dock", category: "video")

/// Holds a browser's Picture in Picture video in the notch. While one floats, the tab beside the closed notch
/// (and "Video" in the open dropdown) offers to hold it; dragging the video onto the notch does too. Open, it
/// sits on the right of the time; closed, the notch grows down around it as a mini player. Drag it away to
/// give it back to the browser.
///
/// The video is the browser's real window, below Jarvis's panel, showing through a hole in the notch cut to
/// the frame it actually got (browsers keep their own aspect ratio). Changes play in separate steps: the cover
/// the clamshell comes on, the notch grows or shrinks, the video moves, and the clamshell fades off again, so the
/// video never shows outside the notch and nothing see-through ever shows.
@MainActor
@Observable
final class VideoController {
    /// Where the held video window really is on screen; the clamshell is drawn over exactly this.
    private(set) var frameOnScreen: CGRect?

    @ObservationIgnored private let state: AppState
    @ObservationIgnored private let windows: WindowControlling
    @ObservationIgnored private var window: ForeignWindow?
    /// Where the browser had it, to give it back there.
    @ObservationIgnored private var original: CGRect?
    /// The open dropdown's spot for it, in shape coordinates.
    @ObservationIgnored private var openSlot: CGRect?
    @ObservationIgnored private var move = 0
    @ObservationIgnored private var watcher: Timer?
    @ObservationIgnored private var poll: Timer?
    /// Checks a showing video is still in its spot (one Accessibility read, only while one is held).
    @ObservationIgnored private var spotCheck: Timer?
    /// Times in a row the video was put back in the same spot; macOS can insist on nudging it (near the menu bar),
    /// and after two tries it's left where macOS wants it rather than fought over.
    @ObservationIgnored private var corrections: (spot: CGRect, count: Int)?
    @ObservationIgnored private var catcher = DockCatch(catchMargin: 40, releaseMargin: 90)
    /// The video being pressed on, where it started, and whether it was held then.
    @ObservationIgnored private var pressed: (window: ForeignWindow, start: CGRect, wasHeld: Bool)?

    /// The clamshell closing or opening, before anything else moves.
    static let cover = 0.22
    /// Closing: the video moving into the mini spot under the clamshell (`travel`), before the notch shrinks.
    static let shrink = travel + 0.04
    /// How long the notch takes to grow or shrink before the video is revealed. Shorter than the springs in
    /// `NotchMotion` run: they look settled well before they end, and waiting them out made the reveal ~0.4 s late.
    static let reshape = 0.35
    /// Opening, the notch drops and then widens (`NotchMotion.expandDelay` + `expand`), which takes longer: moving
    /// the video at `reshape` put it at its big spot while the panel was still growing out to it, so it showed
    /// past the panel's edge (plain to see on skins with a coloured background and border, like Pink).
    static let reshapeOpening = 0.55
    /// Each half of the clamshell's move from the video's old spot to its new one (see `moveUnderCover`): its far
    /// corner reaching out, then its near corner drawing in.
    static let reach = 0.13
    static let travel = 2 * reach
    /// How long the notch waits before it moves, with a video held (see `NotchView`).
    static func notchDelay(opening: Bool) -> Double { opening ? cover : cover + shrink }
    /// The hole sits `holeInset` inside the video with corners this round. A rounded rectangle inset by d stays
    /// inside the original if its radius is at least the original's minus d, so this covers browser video
    /// windows rounded up to 18 pt (Firefox's showed through at 12).
    nonisolated static let cornerRadius: CGFloat = NotchLayout.videoHoleRadius
    nonisolated static let holeInset: CGFloat = NotchLayout.videoHoleInset
    /// The clamshell reaches this far past the video's edges, so none of it shows while it moves.
    nonisolated static let coverOutset: CGFloat = 1

    init(state: AppState, windows: WindowControlling = AXWindowControl()) {
        self.state = state
        self.windows = windows
        // Notices a video popping out (or closing) while the notch is shut, for the tab's video button.
        poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        spotCheck = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepInSpot() }
        }
    }

    func refresh() {
        let found = windows.pictureInPicture()
        if state.video.available != (found != nil) {
            log.debug("video: \(found == nil ? "gone" : "found one in pid \(found!.pid)")")
            state.updateVideo { $0.available = found != nil }
        }
        if state.video.held, let window, windows.frame(of: window) == nil { forget() }
    }

    func slotMoved(_ inShape: CGRect) {
        let old = openSlot
        openSlot = inShape
        // The dropdown's layout shifted under a video that's showing: it follows.
        if let old, abs(old.minX - inShape.minX) + abs(old.minY - inShape.minY) > 1 { keepInSpot() }
    }

    /// Once a video is showing in its spot (not mid-move, not being dragged), puts it back if it has drifted:
    /// macOS or the browser can move it afterwards (setting a window aside moved it), and the hole used to follow
    /// it off the spot, over the music row.
    private func keepInSpot() {
        // Not while the notch is opening or closing: `spot` switches to the new stage's at once, and putting the
        // video "back" there moved it before the notch (and the clamshell) had got there. The clamshell is on
        // (`covered`) for the whole of a move; `wasOpen` catches the moment before `modeChanged` runs.
        guard !state.video.covered, (state.notch.mode == .open) == wasOpen else { return }
        guard state.video.held, !state.video.tucked, holeOpen, pendingTheater == nil, watcher == nil,
              let window, let spot, let now = windows.frame(of: window) else { return }
        guard abs(now.minX - spot.minX) > 2 || abs(now.maxY - spot.maxY) > 2 else { return }
        let count = corrections?.spot == spot ? corrections!.count + 1 : 1
        corrections = (spot, count)
        guard count <= 2 else { return }
        log.debug("video: drifted to \(Int(now.minX)),\(Int(now.maxY)), back to \(Int(spot.minX)),\(Int(spot.maxY))")
        place()
    }

    // MARK: Where things are

    /// The notch shape's top-left corner on screen, and its width, for the stage the video is going to.
    private var shapeOrigin: CGPoint {
        let open = state.notch.mode == .open
        let skin = state.skin
        let width = state.layout.size(for: open ? .open : .idle).width + (open ? 2 * skin.shoulder : 0)
        return CGPoint(x: state.layout.notch.midX - width / 2, y: state.layout.notch.maxY + (open ? skin.lift : 0))
    }

    private func toScreen(_ rect: CGRect) -> CGRect {
        let o = shapeOrigin
        return CGRect(x: o.x + rect.minX, y: o.y - rect.maxY, width: rect.width, height: rect.height)
    }

    private func toShape(_ rect: CGRect) -> CGRect {
        let o = shapeOrigin
        return CGRect(x: rect.minX - o.x, y: o.y - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where the video belongs right now, on screen.
    var spot: CGRect? {
        guard state.video.held, !state.video.tucked else { return nil }
        if state.notch.mode == .open {
            return state.video.theater ? state.layout.theaterVideoFrame : openSlot.map(toScreen)
        }
        return state.layout.miniVideoFrame
    }

    // MARK: Keep Large

    /// A switch into or out of theater that's under way.
    @ObservationIgnored private var pendingTheater: Bool?
    @ObservationIgnored private var wasOpen = false
    /// The hole over the video is cut. It stays cut while the clamshell closes over the video (filling it at once
    /// made solid skins look blocked with no animation) and opens again as the clamshell parts.
    private(set) var holeOpen = false
    /// The dropdown's text is faded out while the video moves between it and Large: out before the video leaves
    /// for Large, back in once it has settled in the dropdown.
    private(set) var panelHidden = false
    /// The pointer is over the video, so its ↑ ↓ tabs show (Large and the mini player).
    private(set) var pointerOverVideo = false

    /// Keep Large: the open notch is just the video, bigger. Each switch plays behind the clamshell: it closes,
    /// the notch reshapes, the video moves, it opens.
    func sync() {
        guard state.video.held else {
            if state.video.theater { state.updateVideo { $0.theater = false } }
            return
        }
        let wanted = state.dock.keep == .large && state.notch.mode == .open
        // Compared with where it's heading, not where it is, so hovering in and out mid-switch ends up right.
        guard wanted != (pendingTheater ?? state.video.theater) else { return }
        guard wanted != state.video.theater else {
            // Back to what's showing before the switch happened: call it off and just reopen.
            pendingTheater = nil
            state.updateVideo { $0.tallForTheater = false }
            panelHidden = false
            settle(after: 0.05)
            return
        }
        pendingTheater = wanted
        state.updateVideo { $0.covered = true }
        panelHidden = true
        // Either way the dropdown first deepens to Large's depth (still full width), so the video and its
        // clamshell stay inside it while they move. Into Large: the video moves to its big spot, then the dropdown
        // narrows around it. Out of Large: the dropdown widens, the video moves into its spot, and the extra depth
        // goes. `settle` takes the move number first, so the steps below share it.
        let deepen = 0.22, moveGap = 0.16
        // Out of Large the video moves here, in `settle`, while the dropdown is still deep.
        let settling = Self.cover + deepen + Self.travel + moveGap + Self.reshape
        settle(after: settling)
        let current = move
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cover) { [weak self] in
            guard let self, current == move else { return }
            holeOpen = false
            state.updateVideo { $0.tallForTheater = true; if !wanted { $0.theater = false } }
            DispatchQueue.main.asyncAfter(deadline: .now() + deepen) {
                guard current == self.move else { return }
                var moving = 0.0
                if wanted, let window = self.window, let big = self.state.layout.theaterVideoFrame {
                    moving = self.moveUnderCover(window, to: big)
                }
                // The dropdown narrows only once the clamshell has drawn in onto the big spot, so it never pokes
                // out past the dropdown's edge.
                DispatchQueue.main.asyncAfter(deadline: .now() + moving + moveGap) {
                    guard current == self.move else { return }
                    self.pendingTheater = nil
                    self.state.updateVideo { $0.theater = wanted }
                }
            }
        }
        // Once the video sits in its new spot (and the clamshell has drawn in), the dropdown loses the extra depth,
        // then its text fades back in.
        let settled: Double = settling + Self.travel + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + settled) { [weak self] in
            guard let self, current == move else { return }
            state.updateVideo { $0.tallForTheater = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + settled + 0.15) { [weak self] in
            guard let self, current == move else { return }
            panelHidden = false
        }
    }

    // MARK: The ↑ ↓ tabs

    /// The tabs show over the video while the pointer is on it. ↑ always (smaller: full dropdown → Large → mini
    /// → tucked); ↓ except on the full dropdown, which is as big as it gets.
    var showsControls: Bool { holeOpen && pointerOverVideo }

    var showsDown: Bool { !(state.notch.mode == .open && !state.video.theater) }

    /// Where the tabs are on screen (↑, then ↓ if shown), in the middle of the video; clicks there are Jarvis's.
    var controlFrames: [CGRect] {
        guard let f = frameOnScreen else { return [] }
        let size = Self.tabSize
        guard showsDown else {
            return [CGRect(x: f.midX - size.width / 2, y: f.midY - size.height / 2, width: size.width, height: size.height)]
        }
        return [CGRect(x: f.midX - size.width / 2, y: f.midY + 2, width: size.width, height: size.height),
                CGRect(x: f.midX - size.width / 2, y: f.midY - 2 - size.height, width: size.width, height: size.height)]
    }

    nonisolated static let tabSize = CGSize(width: 40, height: 18)

    func pointer(at point: CGPoint) {
        let over = holeOpen && (frameOnScreen?.contains(point) ?? false)
        if over != pointerOverVideo { pointerOverVideo = over }
        // Not on held apps' tab, which sits in front of it along the top.
        let onApps = state.layout.showsTab && state.layout.tabFrame.contains(point)
        let overTab = morph == nil && !onApps && state.layout.videoTabFrame?.contains(point) == true
        if overTab != pointerOverTab { pointerOverTab = overTab }
    }

    /// ↑, one size smaller: the full dropdown → Large; Large → the mini player; the mini player → tucked away.
    func up() {
        if state.notch.mode == .open {
            if state.video.theater {
                state.send(.dismiss)
            } else {
                state.updateDock { $0.keep = .large }
                sync()
            }
        } else {
            tuck()
        }
    }

    /// ↓, one size bigger: the mini player → Large (opened and kept); Large → the full dropdown.
    func down() {
        if state.notch.mode == .open {
            guard state.video.theater else { return }
            // Up to the full dropdown: Keep Info goes back to what it was last set to.
            state.updateDock { $0.keep = $0.keepInfo }
            sync()
        } else {
            // Theater first, so the notch opens straight to the big video, never the full dropdown on the way.
            state.updateDock { $0.keep = .large }
            state.updateVideo { $0.theater = true }
            state.send(.summon)
        }
    }

    /// The tuck, in steps, the video always hidden behind the skin while it moves: the clamshell closes over
    /// the mini player; the cover widens right over where the video will wait (the video moves there behind
    /// it); the cover shrinks in from the left and rises into the side tab's place; then the video icon appears.
    /// It can't go higher: macOS keeps windows below the menu bar.
    private(set) var morph: TuckMorph?

    /// The mini player's shape as a morph (the closed notch around the video, shoulders and all).
    private func miniShape(_ body: CGRect) -> TuckMorph {
        let sh = state.skin.shoulder
        return TuckMorph(frame: body.insetBy(dx: -sh, dy: 0), leftShoulder: sh, rightShoulder: sh,
                         radius: NotchLayout.videoCornerRadius)
    }

    /// The tucked tab's shape as a morph.
    private func tabShape(_ tab: CGRect) -> TuckMorph {
        TuckMorph(frame: CGRect(x: tab.minX, y: tab.minY, width: tab.width + 6, height: tab.height),
                  leftShoulder: 0, rightShoulder: 6, radius: 10, leftEdgeTop: state.layout.notch.height)
    }

    /// Without animation, so the real notch can change underneath the cover in one frame.
    private func instantly(_ change: () -> Void) {
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant, change)
    }

    private func tuck() {
        guard state.video.held, !state.video.tucked, state.layout.miniVideoFrame != nil else { return }
        let start = state.layout.frame(for: .idle)
        state.updateVideo { $0.covered = true }
        move += 1
        let current = move
        let notch = state.layout.notch
        let pad = NotchLayout.videoPad
        // Where the tucked video and its tab will be (the browser's smallest, Firefox's 59×33).
        var after = state.layout
        after.videoAspect = nil
        after.tuckedVideo = CGSize(width: 59, height: 33)
        guard let tab = after.videoTabFrame else { return }
        let mini = miniShape(start), final = tabShape(tab)
        let step = { [weak self] (delay: Double, work: @escaping @MainActor () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let self, current == self.move else { return }
                work()
            }
        }
        step(Self.cover) {
            // The cover takes over exactly as the mini player looks, and the real notch becomes plain underneath
            // it in the same frame: from here only this one shape moves.
            self.holeOpen = false
            self.pointerOverVideo = false
            self.instantly {
                self.morph = mini
                self.state.updateVideo { $0.tucked = true; $0.tuckedSize = after.tuckedVideo }
            }
            // 1: the right side goes out over where the video will wait.
            withAnimation(.easeInOut(duration: 0.22)) {
                self.morph?.frame.size.width = max(mini.frame.maxX, final.frame.maxX) - mini.frame.minX
            }
        }
        step(Self.cover + 0.26) {
            // Covered all the way across: the video moves under it.
            guard let window = self.window else { return }
            let tiny = CGRect(x: notch.maxX + pad, y: notch.minY - 33, width: 59, height: 33)
            var got = self.windows.setFrame(tiny, of: window) ?? tiny
            got = self.windows.setFrame(CGRect(x: notch.maxX + pad, y: notch.minY - got.height,
                                               width: got.width, height: got.height), of: window) ?? got
            self.frameOnScreen = got
            log.debug("video: tucked at \(Int(got.width))x\(Int(got.height))")
            if got.size != after.tuckedVideo { self.state.updateVideo { $0.tuckedSize = got.size } }
        }
        step(Self.cover + 0.34) {
            // 2: the left side comes in (and loses its shoulder: the tab meets the notch).
            withAnimation(.easeInOut(duration: 0.24)) {
                guard var m = self.morph else { return }
                m.frame = CGRect(x: final.frame.minX, y: m.frame.minY, width: m.frame.maxX - final.frame.minX, height: m.frame.height)
                m.leftShoulder = 0
                m.leftEdgeTop = final.leftEdgeTop
                self.morph = m
            }
        }
        step(Self.cover + 0.66) {
            // 3: up into the tab, with a small bounce (small enough never to uncover the video under it).
            withAnimation(.spring(duration: 0.38, bounce: 0.18)) { self.morph = final }
        }
        step(Self.cover + 1.06) {
            withAnimation(.easeOut(duration: 0.15)) { self.morph?.icon = true }
        }
        step(Self.cover + 1.24) { self.morph = nil }
    }

    /// The tab is under the pointer while tucked: it bounces out a little and stays out until the pointer leaves.
    private(set) var pointerOverTab = false

    /// Back into the mini player (clicking the side tab), the tuck played backwards with the one shape, so the
    /// video is never seen moving: the icon goes, the tab drops to the mini player's depth, its left side goes
    /// out over the mini spot, a beat, then (the video having moved behind it) its right side comes in to the
    /// mini player, and the clamshell opens. It stays until ↑ again.
    func untuck() {
        guard state.video.tucked, let window else { return }
        move += 1
        let current = move
        pointerOverTab = false
        var mini = state.layout
        mini.tuckedVideo = nil
        mini.videoAspect = state.video.aspect
        let end = mini.frame(for: .idle)
        guard let spot = mini.miniVideoFrame else { return }
        guard let tab = state.layout.videoTabFrame else { return }
        let start = tabShape(tab), target = miniShape(end)
        let step = { [weak self] (delay: Double, work: @escaping @MainActor () -> Void) in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let self, current == self.move else { return }
                work()
            }
        }
        var first = start
        first.icon = true
        instantly { morph = first }
        withAnimation(.easeIn(duration: 0.12)) { morph?.icon = false }
        step(0.14) {
            // Down to the mini player's depth.
            withAnimation(.easeInOut(duration: 0.26)) {
                guard var m = self.morph else { return }
                m.frame = CGRect(x: m.frame.minX, y: target.frame.minY, width: m.frame.width, height: target.frame.height)
                m.radius = target.radius
                self.morph = m
            }
        }
        step(0.44) {
            // The left side out over the mini spot, shoulder and all.
            withAnimation(.easeInOut(duration: 0.3)) {
                guard var m = self.morph else { return }
                m.frame = CGRect(x: target.frame.minX, y: m.frame.minY, width: m.frame.maxX - target.frame.minX, height: m.frame.height)
                m.leftShoulder = target.leftShoulder
                m.leftEdgeTop = 0
                self.morph = m
            }
        }
        step(0.8) {
            // Covered: the video moves to the mini spot, and the real notch becomes the mini player (clamshell shut)
            // underneath, in one frame.
            let got = self.windows.setFrame(spot, of: window) ?? spot
            self.instantly {
                self.frameOnScreen = got
                self.state.updateVideo { $0.tucked = false; $0.covered = true }
            }
        }
        step(0.9) {
            // A beat after the left side, the right side comes in: the shape is the mini player.
            withAnimation(.easeInOut(duration: 0.26)) { self.morph = target }
        }
        step(1.2) {
            self.morph = nil
            self.settle(after: 0.05)
        }
    }

    // MARK: Holding and letting go

    func hold() {
        guard !state.video.held, let found = windows.pictureInPicture(), let frame = windows.frame(of: found) else { return }
        window = found
        original = frame
        frameOnScreen = frame
        holeOpen = false
        state.updateVideo { $0.held = true; $0.catching = false; $0.covered = true; $0.tucked = false
                            $0.aspect = frame.width / max(frame.height, 1) }
        settle(after: state.notch.mode == .open ? 0.1 : Self.reshape)
    }

    /// Given back to the browser in the screen's bottom-right corner (where browsers put Picture in Picture),
    /// half again as big as it was (at least 420 pt wide, at most 45% of the screen). Not where it came from: a
    /// video dragged in last sat right under the notch, and going back there looked like it was hiding behind
    /// the dropdown.
    func giveBack() {
        guard let window, let original else { return forget() }
        let area = state.notchScreen?.visibleFrame ?? .zero
        let margin: CGFloat = 20
        let width = min(max(original.width * 1.5, 420), area.width * 0.45).rounded()
        let height = (width * original.height / max(original.width, 1)).rounded()
        windows.setFrame(CGRect(x: area.maxX - width - margin, y: area.minY + margin, width: width, height: height),
                         of: window)
        forget()
    }

    private func forget() {
        window = nil
        original = nil
        frameOnScreen = nil
        holeOpen = false
        pointerOverVideo = false
        watcher?.invalidate()
        watcher = nil
        pressed = nil
        state.updateVideo { $0.held = false; $0.covered = true; $0.tucked = false; $0.theater = false }
    }

    // MARK: Following the notch

    /// The notch is about to change shape (it waits `notchDelay` first, see `NotchView`). Opening: the clamshell
    /// comes on, the notch grows, the video moves into the dropdown, the clamshell fades. Closing: the clamshell comes on,
    /// closes, the video shrinks into the mini spot (hidden under the solid notch), then the notch shrinks around
    /// it and the clamshell fades.
    func modeChanged(to mode: NotchMode) {
        refresh()
        // A hover peek (closed ↔ peek) leaves the video where it is; only opening and closing move it.
        let open = mode == .open
        defer { wasOpen = open }
        guard state.video.held, open != wasOpen else { return }
        // Closing leaves theater, but only once the notch has closed: clearing it at once flashed the full dropdown
        // on the way down. It comes back on reopening via `sync`.
        pendingTheater = nil
        if mode != .open, state.video.theater {
            let closing = move + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.notchDelay(opening: false) + 0.9) { [weak self] in
                guard let self, state.notch.mode != .open, move <= closing + 1 else { return }
                state.updateVideo { $0.theater = false }
            }
        }
        let opening = mode == .open
        panelHidden = false
        state.updateVideo { $0.covered = true }
        settle(after: Self.notchDelay(opening: opening) + (opening ? Self.reshapeOpening : Self.reshape))
        if opening {
            // Opening with Keep Large and the pointer away goes straight to theater once open.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.notchDelay(opening: true) + Self.reshapeOpening + 0.4) { [weak self] in
                self?.sync()
            }
        }
        let current = move
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cover) { [weak self] in
            guard let self, current == move else { return }
            // The clamshell is shut: the hole fills, and the video can move, the clamshell going with it. Closing,
            // it moves into the mini spot inside the still-open dropdown; the notch shrinks once it's there
            // (`shrink`).
            holeOpen = false
            if !opening, let window, let spot { moveUnderCover(window, to: spot) }
        }
    }

    private func settle(after delay: Double) {
        // A fresh move: drift is put back again, however often it was before.
        corrections = nil
        move += 1
        let current = move
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, current == move, state.video.held, !state.video.tucked else { return }
            let gliding = place()
            // Let the browser redraw at its new size (and the clamshell get there) before the clamshell parts off it.
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, gliding)) {
                guard current == self.move else { return }
                self.holeOpen = true
                self.state.updateVideo { $0.covered = false }
            }
        }
    }

    /// Moves the video to its spot and cuts the hole to the frame it really got. Returns how long the clamshell
    /// takes to follow it there.
    @discardableResult private func place() -> Double {
        guard let window, let spot else { return 0 }
        return moveUnderCover(window, to: spot) { [weak self] got in self?.placed(got, in: spot) }
    }

    /// The video landed at `got` (asked for `spot`): a browser that won't go that small is remembered, and the
    /// hole follows macOS nudging it afterwards.
    private func placed(_ landed: CGRect, in spot: CGRect) {
        guard let window else { return }
        var got = landed
        if got.width > spot.width + 1 || got.height > spot.height + 1 {
            // The browser won't make it that small: remember its smallest. The notch makes room for it at once
            // (the layout grows), so the video goes straight to its grown spot; the open dropdown's spot is
            // measured again by SwiftUI, so that one is placed once more a moment later.
            log.debug("video: smallest is \(Int(got.width))x\(Int(got.height))")
            state.updateVideo { $0.minimum = got.size }
            if let grown = self.spot {
                got = windows.setFrame(grown, of: window) ?? grown
                coverAtOnce(got)
            }
            if state.notch.mode == .open {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.place() }
            }
        }
        // macOS can still nudge a window this close to the menu bar after saying where it is: look again once
        // it has settled (and the clamshell has drawn in), and follow it, so the hole is never off the video (it
        // showed as the top cut off).
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reach + 0.15) { [weak self] in
            guard let self, let window = self.window, let now = windows.frame(of: window), now != frameOnScreen else { return }
            log.debug("video: moved after placing, \(Int(got.minY)) -> \(Int(now.minY))")
            coverAtOnce(now)
        }
    }

    /// Moves the video to `target` with the clamshell over it the whole way, so neither jumps: the clamshell's
    /// far corner reaches out until it spans both spots, the video moves underneath, then its near corner draws in
    /// onto the frame the video got. The video is never outside it, so this works on see-through Liquid Glass too.
    /// The caller keeps the notch big enough for both spots meanwhile. While the video is showing (no clamshell),
    /// both just go there at once. `done` gets the frame the video got; returns how long the clamshell takes.
    @discardableResult
    private func moveUnderCover(_ window: ForeignWindow, to target: CGRect,
                                done: @escaping (CGRect) -> Void = { _ in }) -> Double {
        guard state.video.covered, !holeOpen, let old = frameOnScreen,
              abs(old.minX - target.minX) + abs(old.minY - target.minY) + abs(old.width - target.width)
                  + abs(old.height - target.height) > 2 else {
            let got = windows.setFrame(target, of: window) ?? target
            coverAtOnce(got)
            done(got)
            return 0
        }
        let current = move
        withAnimation(.easeIn(duration: Self.reach)) { frameOnScreen = old.union(target) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reach) { [weak self] in
            // A newer move (or letting go) took over: it starts from wherever the clamshell is now.
            guard let self, current == move, state.video.held else { return }
            let got = windows.setFrame(target, of: window) ?? target
            withAnimation(.easeOut(duration: Self.reach)) { frameOnScreen = got }
            done(got)
        }
        return Self.travel
    }

    private func coverAtOnce(_ frame: CGRect) {
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        withTransaction(instant) { frameOnScreen = frame }
    }

    // MARK: Dragging the video in and out

    /// A press on the video: if the user then drags it away from its spot, it's let go; if a loose video is
    /// dragged onto the notch, it's held.
    func mouseDown(at point: CGPoint) {
        guard watcher == nil, let found = windows.pictureInPicture(), let start = windows.frame(of: found),
              start.contains(point) else { return }
        pressed = (found, start, state.video.held)
        catcher = DockCatch(catchMargin: 40, releaseMargin: 90)
        watcher = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
    }

    private func watch() {
        guard let (found, start, wasHeld) = pressed else { return }
        let down = NSEvent.pressedMouseButtons & 1 != 0
        let now = windows.frame(of: found)
        let moved = now.map { abs($0.minX - start.minX) + abs($0.minY - start.minY) > 12 } ?? false
        if wasHeld {
            // Dragged out of the notch: it's the browser's again, wherever it's dropped.
            if moved {
                window = nil
                original = nil
                frameOnScreen = nil
                holeOpen = false
                pointerOverVideo = false
                stopWatching()
                state.updateVideo { $0.held = false; $0.covered = true; $0.theater = false }
            } else if !down {
                stopWatching()
            }
            return
        }
        // A loose video dragged up to the notch. Windows can't go above the menu bar, so it's the window's top
        // edge that's caught, not the pointer: the dropdown opens to show it'll go in, and closes if it's
        // dragged away again.
        if moved, let now,
           catcher.update(pointer: CGPoint(x: now.midX, y: now.maxY), catchIn: state.layout.notch,
                          releaseOutside: state.layout.notch) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            // The dropdown opens with an outline of the video where it'll go.
            state.updateVideo { $0.catching = catcher.caught; $0.aspect = now.width / max(now.height, 1) }
            state.send(catcher.caught ? .summon : .dismiss)
        }
        guard !down else { return }
        stopWatching()
        if catcher.caught { hold() } else if state.video.catching { state.updateVideo { $0.catching = false } }
    }

    private func stopWatching() {
        watcher?.invalidate()
        watcher = nil
        pressed = nil
    }
}

/// The one shape that moves while the video tucks away or comes back: drawn like the notch (shoulders, border,
/// glow), in screen coordinates. `frame` includes the shoulders; `leftEdgeTop` is how far down its left
/// outline starts (0 for the notch, the notch's height for the tab, which meets the notch above that).
struct TuckMorph: Equatable {
    var frame: CGRect
    var leftShoulder: CGFloat
    var rightShoulder: CGFloat
    var radius: CGFloat
    var leftEdgeTop: CGFloat = 0
    var icon = false
}
