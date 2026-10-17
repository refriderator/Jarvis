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

    @MainActor
    private final class Tray {
        let panel = NotchPanel()
        let model: TrayModel
        let screen: NSScreen
        /// A dragged window's title bar is at this display's top middle.
        var dragNear = false
        var hovering = false

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

    /// One tray per display other than the notch's (after a display is plugged in, or the notch moves).
    func rebuild() {
        trays.values.forEach { $0.panel.orderOut(nil) }
        trays = [:]
        let notched = state.notchScreen
        for screen in NSScreen.screens where screen != notched {
            guard let id = screen.displayID else { continue }
            let hardware = screen.safeAreaInsets.top > 0 ? screen.notchLayout.notch : nil
            let layout = TrayLayout(screen: screen.frame, menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                                    hardwareNotch: hardware)
            let tray = Tray(model: TrayModel(layout: layout), screen: screen)
            tray.panel.ignoresMouseEvents = false
            tray.panel.contentView = NSHostingView(rootView: TrayView(model: tray.model, state: state, dock: dock))
            trays[id] = tray
        }
        refresh()
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
            let stage: TrayStage = tray.dragNear ? .open : apps.isEmpty ? .hidden : tray.hovering ? .open : .dot
            show(stage, tray)
        }
        let up = trays.values.contains { $0.model.stage != .hidden }
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
                                     : layout.frame(for: max(tray.model.stage, .dot)).insetBy(dx: -2, dy: -2)
            let hovering = !tray.model.apps.isEmpty && zone.contains(pointer)
            if hovering != tray.hovering {
                tray.hovering = hovering
                changed = true
            }
        }
        if changed { refresh() }
    }

    /// Grows the panel before the tray animates bigger, and shrinks it (or hides it) once it has animated smaller,
    /// so it never covers more of the menu bar and title bars than the tray does.
    private func show(_ stage: TrayStage, _ tray: Tray) {
        let old = tray.model.stage
        guard stage != old else { return }
        if stage > old {
            tray.panel.setFrame(panelFrame(stage, tray), display: true)
            tray.panel.orderFrontRegardless()
        }
        tray.model.stage = stage
        guard stage < old else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, tray.model.stage == stage else { return }
            if stage == .hidden {
                tray.panel.orderOut(nil)
            } else {
                tray.panel.setFrame(panelFrame(stage, tray), display: true)
            }
        }
    }

    private func panelFrame(_ stage: TrayStage, _ tray: Tray) -> CGRect {
        let frame = tray.model.layout.frame(for: max(stage, .dot))
        let room = Self.glowRoom
        return CGRect(x: frame.minX - room, y: frame.minY - room, width: frame.width + 2 * room, height: frame.height + room)
    }
}
