import AppKit
import JarvisKit
import SwiftUI

/// Displays other than the notch's get a tray of their own for the windows held on the desktop they're showing,
/// 6 per desktop like the notch (`TrayLayout` has the shapes). Holding nothing, there's no tray; holding windows,
/// a small notch with a white dot; hovered, or a window dragged by its title bar to the top middle, it opens to a
/// 2 × 3 grid. Let go there and the window is held on that display (`DockController` asks `catches`). Click an icon
/// to bring its window back filling the desktop, drag it out to carry the window.
@MainActor
final class ScreenTrays {
    private let state: AppState
    private let dock: DockController
    private var trays: [CGDirectDisplayID: Tray] = [:]
    private var observers: [NSObjectProtocol] = []
    /// Follows the pointer while a tray is up, to open it on hover and close it after.
    private var hoverTimer: Timer?
    /// Displays with an app full screen (`FullScreenWatch`): a tray there hides until the pointer reaches the top edge.
    var fullScreen: Set<CGDirectDisplayID> = [] {
        didSet { if fullScreen != oldValue { refresh() } }
    }
    /// Mission Control is open (`MissionControlWatch`): every tray goes, as the notch fades. They sit above it, so
    /// out there they took its clicks and opened under the pointer.
    var missionControl = false {
        didSet {
            guard missionControl != oldValue else { return }
            if missionControl { trays.values.forEach { $0.heldOff = true } }
            refresh()
        }
    }

    @MainActor
    private final class Tray {
        let panel = NotchPanel()
        let model: TrayModel
        /// Rising off and dropping on when the notch changes display, like the notch.
        let hop = NotchHop()
        let screen: NSScreen
        /// A dragged window's title bar is at this display's top middle.
        var dragNear = false
        var hovering = false
        /// Hidden up against the top edge for a full-screen app (`FullScreen`).
        var tucked = false
        /// Since Mission Control opened, the pointer hasn't left the tray: its desktops bar is up there too, and
        /// a desktop picked there leaves the pointer on the tray, which mustn't open for that.
        var heldOff = false

        init(model: TrayModel, screen: NSScreen) {
            self.model = model
            self.screen = screen
        }
    }

    /// Room in the panel around the tray for the skin's glow.
    static let glowRoom: CGFloat = 16

    init(state: AppState, dock: DockController) {
        self.state = state
        self.dock = dock
        dock.overTray = { [weak self] pointer in self?.catches(pointer) ?? false }
        rebuild()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuild() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observeApps()
    }

    private func observeApps() {
        withObservationTracking {
            _ = state.dock.apps
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeApps()
            }
        }
    }

    /// The notch is moving to another display: every tray goes with it (`rebuild(arriving:)` brings the new ones).
    /// As for the notch: a tray rises away and stretches only where there's no hardware notch; beside one, its
    /// tab tucks in behind the notch (open, hanging below it, it rises into it).
    func leave() {
        for tray in trays.values where tray.model.stage != .hidden {
            let layout = tray.model.layout
            tray.hop.leave(height: layout.frame(for: tray.model.stage).height,
                           rises: !layout.isBeside(tray.model.stage), springy: layout.hardwareNotch == nil)
        }
    }

    /// One tray per display other than the notch's (after a display is plugged in, or the notch moves). `arriving`:
    /// they drop in from above, after `leave`.
    func rebuild(arriving: Bool = false) {
        trays.values.forEach { $0.panel.orderOut(nil) }
        trays = [:]
        let notched = state.notchScreen
        for screen in NSScreen.screens where screen != notched {
            guard let id = screen.displayID else { continue }
            let hardware = screen.safeAreaInsets.top > 0 ? screen.notchLayout.notch : nil
            let layout = TrayLayout(screen: screen.frame, menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                                    hardwareNotch: hardware)
            let tray = Tray(model: TrayModel(layout: layout), screen: screen)
            // Takes clicks only while the pointer is on the tray (`trackHover`): it covers every stage.
            tray.panel.ignoresMouseEvents = true
            tray.panel.setFrame(panelFrame(layout), display: false)
            tray.panel.contentView = NSHostingView(rootView: Hopping(hop: tray.hop, content: TrayView(
                model: tray.model, state: state, dock: dock)))
            trays[id] = tray
        }
        refresh()
        guard arriving else { return }
        for tray in trays.values where tray.model.stage != .hidden {
            let layout = tray.model.layout
            let model = tray.model
            tray.hop.arrive(height: { layout.frame(for: model.stage).height },
                            rises: { !layout.isBeside(model.stage) }, springy: { layout.hardwareNotch == nil })
        }
    }

    /// A window dragged by its title bar is at `pointer` (nil: the drag ended). Opens the tray of the display
    /// whose top middle it's at; true when letting go now would hold it there.
    func catches(_ pointer: CGPoint?) -> Bool {
        var caught = false
        for tray in trays.values {
            let layout = tray.model.layout
            // Once open it stays open over the whole drop area, which reaches lower than where it opened.
            let near = pointer.map { layout.approachZone.contains($0) || tray.dragNear && layout.dropZone.contains($0) } ?? false
            let over = near && pointer.map(layout.dropZone.contains) == true
            tray.dragNear = near
            if tray.model.catching != over { tray.model.catching = over }
            caught = caught || over
        }
        refresh()
        return caught
    }

    /// Each tray's held apps (its display's desktop's) and how much of it shows.
    private func refresh() {
        for (id, tray) in trays {
            let desktop = Desktops.active(on: id)
            let apps = state.dock.apps.filter { $0.desktop != nil && $0.desktop == desktop }
            if tray.model.apps != apps { tray.model.apps = apps }
            // Beside a hardware notch the tab sits in the black band a full-screen app leaves, so it stays.
            tray.tucked = fullScreen.contains(id) && tray.model.layout.hardwareNotch == nil
            let stage: TrayStage = missionControl ? .hidden
                : tray.dragNear || tray.hovering ? .open : apps.isEmpty || tray.tucked ? .hidden : .dot
            show(stage, tray)
        }
        // Tucked away, the pointer is still followed, for the top edge.
        let up = trays.values.contains { $0.model.stage != .hidden || !$0.model.apps.isEmpty }
        if up, hoverTimer == nil {
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackHover() }
            }
        } else if !up {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    /// Opens on the pointer coming onto the tray (or the hardware notch it hides behind), closes once it's well off.
    private func trackHover() {
        let pointer = NSEvent.mouseLocation
        var changed = false
        for tray in trays.values {
            let layout = tray.model.layout
            let zone = tray.hovering ? layout.frame(for: .open).insetBy(dx: -12, dy: -12)
                     : tray.tucked ? FullScreen.edge(of: layout.screen, under: layout.frame(for: .open))
                     : layout.frame(for: max(tray.model.stage, .dot)).insetBy(dx: -2, dy: -2)
            // The whole hardware notch counts, though the resting tab is narrower.
            let behind = layout.hardwareNotch?.insetBy(dx: -2, dy: -2) ?? .null
            let near = !tray.model.apps.isEmpty && (zone.contains(pointer) || behind.contains(pointer))
            if !near, !missionControl { tray.heldOff = false }
            let hovering = near && !tray.heldOff
            let onTray = tray.model.stage != .hidden && layout.frame(for: tray.model.stage).insetBy(dx: -4, dy: -4).contains(pointer)
            if tray.panel.ignoresMouseEvents == onTray { tray.panel.ignoresMouseEvents = !onTray }
            if hovering != tray.hovering {
                tray.hovering = hovering
                changed = true
            }
        }
        if changed { refresh() }
    }

    /// Shows the panel before the tray animates in, and hides it once it has animated away. The panel's frame never
    /// changes (it covers every stage), so the tray can be anywhere in it: beside a hardware notch resting, below
    /// it open.
    private func show(_ stage: TrayStage, _ tray: Tray) {
        let old = tray.model.stage
        guard stage != old else { return }
        if old == .hidden { tray.panel.orderFrontRegardless() }
        tray.model.stage = stage
        guard stage == .hidden else { return }
        tray.panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if tray.model.stage == .hidden { tray.panel.orderOut(nil) }
        }
    }

    /// Every stage's frame (`TrayLayout.bounds`), with room for the glow at the sides and below.
    private func panelFrame(_ layout: TrayLayout) -> CGRect {
        let frame = layout.bounds
        let room = Self.glowRoom
        return CGRect(x: frame.minX - room, y: frame.minY - room, width: frame.width + 2 * room, height: frame.height + room)
    }
}
