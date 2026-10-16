import AppKit
import JarvisKit
import SwiftUI

/// Owns the notch panel. Turns pointer and key events into `NotchEvent`s and
/// keeps the panel's mouse/key behavior in step with the current mode.
@MainActor
final class NotchController {
    private let state: AppState
    private let panel = NotchPanel()
    private var monitors: [Any] = []
    private var pointerInside = false
    private var appliedMode: NotchMode = .idle
    private var missionControl: MissionControlWatch?
    private var draggingFile = false
    /// Room around the open panel for the skin's glow.
    private let glowMargin: CGFloat = 40

    private let feed: WidgetFeed
    private let dock: DockController
    private let monitor: MonitorFeed
    private let browser: BrowserController
    private let video: VideoController
    private let notice: NoticePanel
    private var quickDock: QuickDock?
    /// The strips on displays without the notch.
    private var trays: ScreenTrays?

    /// Ends a finished caption after a reading pause.
    private var captionTimer: DispatchWorkItem?
    /// The reading pause ended while the pointer was on the panel; leaving it ends the caption.
    private var captionWaitsForPointer = false
    private var returnFocus: DispatchWorkItem?
    /// Long enough for the closing animation (see `NotchMotion`) to finish.
    private let closeAnimationSeconds = 0.9

    /// The local brain's Mac tools reach the window dock and Quick Dock through here.
    func connect(_ mac: MacControls) {
        mac.dockWindow = { [weak self] app in try self?.dock.dockWindow(of: app) ?? "" }
        mac.undockWindow = { [weak self] app in try self?.dock.undockWindow(of: app) ?? "" }
        mac.setQuickDock = { [state] on in
            guard AccessibilityAccess.isTrusted else {
                throw ChatError("Quick Dock needs Accessibility access: System Settings › Privacy & Security › Accessibility.")
            }
            state.update { $0.quickDock = on }
            return on ? "Quick Dock is on." : "Quick Dock is off."
        }
    }

    init(state: AppState, feed: WidgetFeed, assistant: Assistant, voice: VoiceSession,
         openSettings: @escaping () -> Void, cancelTimer: @escaping (UUID) -> Void) {
        self.state = state
        self.feed = feed
        let dock = DockController(state: state)
        self.dock = dock
        let monitor = MonitorFeed(state: state)
        self.monitor = monitor
        let browser = BrowserController(state: state)
        self.browser = browser
        let video = VideoController(state: state)
        self.video = video
        let notice = NoticePanel(state: state)
        self.notice = notice
        dock.onFileDrag = { [weak self] point in self?.fileDrag(at: point) }
        dock.boxToScreen = { [panel] rect in
            // SwiftUI's global frame is measured from the panel's top-left corner, y going down.
            CGRect(x: panel.frame.minX + rect.minX, y: panel.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        panel.contentView = NSHostingView(rootView: NotchView(state: state, feed: feed, assistant: assistant, voice: voice,
                                                              dock: dock, monitor: monitor, browser: browser, video: video, openSettings: openSettings, cancelTimer: cancelTimer))
        relayout()
        panel.orderFrontRegardless()
        installMonitors()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        // Jarvis steps out of the way of Mission Control and comes back after it.
        trays = ScreenTrays(state: state, dock: dock)
        quickDock = QuickDock(state: state, dock: dock, notice: notice.show)
        missionControl = MissionControlWatch { [weak self] showing in
            guard let self else { return }
            quickDock?.missionControl(showing: showing)
            if showing { state.send(.dismiss) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = showing ? 0.12 : 0.25
                panel.animator().alphaValue = showing ? 0 : 1
            }
            panel.ignoresMouseEvents = showing || state.notch.mode != .open
        }
        observeMode()
        observeCaption()
        observeReady()
    }

    /// Windows held on the sides go back where they were (on quitting, so none are left off the screen).
    func releaseWindows() {
        dock.sides.releaseAll()
    }

    private func relayout() {
        guard let screen = NSScreen.menuBarScreen else { return }
        let layout = screen.notchLayout
        state.updateLayout(layout)
        // Size the window for the biggest the panel gets: open with a caption.
        var biggest = layout
        // A wide video (cinema's 2.4:1) with the Video button showing makes the widest dropdown.
        biggest.videoAspect = 2.4
        biggest.offersVideo = true
        biggest.showsCaption = true
        biggest.captionHeight = max(NotchLayout.maxCaptionHeight, NotchLayout.maxSummaryHeight)
        let open = biggest.frame(for: .open)
        panel.setFrame(CGRect(x: open.minX - glowMargin, y: open.minY - glowMargin,
                              width: open.width + glowMargin * 2, height: open.height + glowMargin),
                       display: true)
    }

    // MARK: Events

    private func installMonitors() {
        let mouse: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouse, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type) }
        }) {
            monitors.append(global)
        }
        // Esc over the medium player arrives while another app has the keyboard, so it's watched for everywhere
        // (seeing other apps' keys needs Accessibility, which holding windows asks for). The key still reaches that app.
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let keyCode = event.keyCode
            MainActor.assumeIsolated { if keyCode == 53 { self?.closeMediumPlayer() } }
        }) {
            monitors.append(keys)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouse.union(.keyDown), handler: { [weak self] event in
            let type = event.type
            // keyCode only exists on key events; reading it on a mouse event throws
            // inside AppKit, which silently drops the click.
            let keyCode = type == .keyDown ? event.keyCode : nil
            let consumed = MainActor.assumeIsolated { self?.handleLocal(type, keyCode: keyCode) ?? false }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }
    }

    /// Esc on the Web tab's medium player (closed notch, a video full screen in the page): pauses it and leaves
    /// full screen, so the notch goes back to normal. False when there's no medium player.
    @discardableResult private func closeMediumPlayer() -> Bool {
        guard state.notch.mode != .open, state.layout.mediumVideoSize != nil else { return false }
        browser.pauseVideos()
        browser.leaveFullscreen()
        return true
    }

    /// Returns true when the event was used up (Esc closing the panel).
    private func handleLocal(_ type: NSEvent.EventType, keyCode: UInt16?) -> Bool {
        if type == .keyDown {
            let escape: UInt16 = 53
            if keyCode == escape, closeMediumPlayer() { return true }
            guard keyCode == escape, state.notch.mode == .open else { return false }
            // Esc closes it even with Keep on; a video playing in the Web tab is paused rather than left playing unseen.
            if state.dock.keep != .off { browser.pauseVideos() }
            state.send(.dismiss)
            return true
        }
        handleMouse(type)
        return false
    }

    private func handleMouse(_ type: NSEvent.EventType) {
        let location = NSEvent.mouseLocation
        video.pointer(at: location)
        let zone = state.layout.hotZone(for: state.notch.mode)
        let inside = zone.contains(location)
        switch type {
        case .leftMouseDown:
            dock.mouseDown(at: location)
            video.mouseDown(at: location)
            state.send(.click(inside: inside))
        default:
            break
        }
        // While the button is down on the Finder tab, a drag (a file out of it, its title off the notch) is
        // under way: the notch waits for it to end before closing.
        let dragging = NSEvent.pressedMouseButtons & 1 != 0 && state.dock.tab == .finder && state.notch.mode == .open
        if inside != pointerInside, inside || !dragging {
            pointerInside = inside
            state.send(inside ? .pointerEntered : .pointerExited)
            if !inside, captionWaitsForPointer, state.captionFinished, !state.captionPinned { closeCaption() }
        }
        updateMouseHandling(at: location)
    }

    /// Only the open notch itself (and the tab beside the closed notch) take clicks, not the see-through
    /// rest of the panel, so what's under them stays usable. A press that started on the panel keeps it until it
    /// comes up, so a drag isn't cut short.
    private func updateMouseHandling(at location: CGPoint) {
        guard !draggingFile else { return }
        let onNotch = state.notch.mode == .open && state.layout.hotZone(for: .open).contains(location)
        let overTab = state.notch.mode != .open && state.layout.showsTab && state.layout.tabFrame.contains(location)
        let pressing = NSEvent.pressedMouseButtons & 1 != 0
        // Over a held video, clicks go through the hole to it, except on its ↑ ↓ tabs.
        let overControls = video.showsControls && video.controlFrames.contains { $0.contains(location) }
        let overVideo = video.holeOpen && video.spot?.contains(location) == true && !overControls
        // The Web tab's medium player takes the click (to open the dropdown), not the window behind it.
        let overMedium = state.notch.mode != .open && state.layout.mediumVideoSize != nil
            && state.layout.frame(for: state.notch.mode).contains(location)
        let ignores = overVideo || (!onNotch && !overTab && !overControls && !overMedium && !(pressing && !panel.ignoresMouseEvents))
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    /// A file being dragged out of the Finder tab: the panel takes the drop only over the notch itself, so a
    /// window just below it gets the file as soon as the pointer is on it. nil when the drag is over.
    private func fileDrag(at point: CGPoint?) {
        draggingFile = point != nil
        guard let point else { return updateMouseHandling(at: NSEvent.mouseLocation) }
        let onNotch = state.layout.hotZone(for: .open).contains(point)
        if panel.ignoresMouseEvents == onNotch { panel.ignoresMouseEvents = !onNotch }
    }

    // MARK: Mode changes

    /// Observation sees `state.notch` as one value, so this also fires when another of its fields is set
    /// (`locked`, `openOnHover`...). Only a real change of mode is acted on: reacting to the rest made a held
    /// video's cover close every time it opened, over and over.
    private func observeMode() {
        withObservationTracking {
            _ = state.notch.mode
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.state.notch.mode != self.appliedMode {
                    self.appliedMode = self.state.notch.mode
                    self.applyMode()
                }
                self.observeMode()
            }
        }
    }

    // MARK: Caption

    /// The caption stays up while it's being answered, even if the pointer leaves, and goes away a
    /// reading pause after it's done. A kept (clicked) caption stays until the user clicks off.
    /// Nothing here opens the notch: a reply never summons a new dropdown.
    private func observeCaption() {
        withObservationTracking {
            _ = state.turns.last?.answer
            _ = state.turns.last?.awaitingCloud
            _ = state.voice
            _ = state.captionActive
            _ = state.captionPinned
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleCaptionEnd()
                self?.observeCaption()
            }
        }
    }

    /// An answer (or a "use the cloud?" question) lands after the dropdown was closed mid-question: pop the
    /// caption back up, silently (typed answers are never read aloud). It then behaves like any caption: it
    /// goes away after a reading pause unless the user clicks it to keep it.
    private func observeReady() {
        withObservationTracking {
            _ = state.turns.last?.answer
            _ = state.turns.last?.awaitingCloud
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.popUpIfClosed()
                self?.observeReady()
            }
        }
    }

    private func popUpIfClosed() {
        guard state.captionActive, state.notch.mode != .open, let turn = state.turns.last,
              turn.answer != nil || turn.awaitingCloud else { return }
        state.send(.summon)
    }

    private func scheduleCaptionEnd() {
        captionTimer?.cancel()
        captionWaitsForPointer = false
        guard state.captionFinished, !state.captionPinned else { return }
        let end = DispatchWorkItem { [weak self] in
            guard let self, state.captionFinished, !state.captionPinned else { return }
            if pointerInside {
                // Being read: wait until the pointer leaves.
                captionWaitsForPointer = true
            } else {
                closeCaption()
            }
        }
        captionTimer = end
        DispatchQueue.main.asyncAfter(deadline: .now() + state.captionLinger, execute: end)
    }

    /// Closes the panel; the caption itself is cleared once it has shrunk away (see `applyMode`).
    private func closeCaption() {
        captionWaitsForPointer = false
        state.send(.dismiss)
    }

    private func applyMode() {
        let isOpen = state.notch.mode == .open
        updateMouseHandling(at: NSEvent.mouseLocation)
        video.modeChanged(to: state.notch.mode)
        returnFocus?.cancel()
        if isOpen {
            // Only on the Today tab does opening take the keyboard; Finder and Monitor are for looking and dragging.
            // Holding a video, opening never takes the keyboard: giving it back means hiding the panel for a frame,
            // which shows as a flash on the mini player.
            if state.dock.tab == .today && state.dock.dragging == nil && !state.video.held { panel.makeKey() }
            feed.panelOpened()
        } else {
            // Once it has shrunk back into the notch: clear the caption (so the list isn't seen coming back
            // mid-close) and hand keyboard focus back to whatever app had it. Hiding and re-showing the panel
            // does that, and doing it earlier would blink through the closing animation.
            let tidy = DispatchWorkItem { [weak self] in
                guard let self, state.notch.mode != .open else { return }
                // A question still being answered keeps its caption, to pop up when the answer is ready.
                if state.turns.last?.isPending != true { state.endCaption() }
                // Never with a video held: the mini player would blink for that frame.
                guard panel.isKeyWindow, !state.video.held else { return }
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
            returnFocus = tidy
            DispatchQueue.main.asyncAfter(deadline: .now() + closeAnimationSeconds, execute: tidy)
        }
        // The hot zone changed size; re-check where the pointer is.
        pointerInside = state.layout.hotZone(for: state.notch.mode).contains(NSEvent.mouseLocation)
    }
}
