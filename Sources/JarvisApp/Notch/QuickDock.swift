import AppKit
import JarvisKit
import os

private let log = Logger(subsystem: "jarvis.dock", category: "quickdock")

/// Quick Dock: one window at a time on each desktop of each display. Turned on, the window in front on every
/// showing desktop fills it and the rest there are set aside in the strip (the notch's, or the tray on a display
/// without one). Desktops not showing yet get the same the first time they're switched to. From then on the app
/// you bring forward (with ⌘-Tab, a click or Mission Control) swaps with the ones in the strip.
///
/// It won't turn on with more than `maxWindows` windows on a showing desktop, and turns itself off when a desktop
/// is moved (or added or closed) in Mission Control, saying so in a small notice under the notch.
@MainActor
final class QuickDock {
    /// The one in front plus a full strip.
    static let maxWindows = NotchDock.maxApps + 1

    private let state: AppState
    private let dock: DockController
    private let windows: WindowControlling
    private let notice: (String) -> Void
    private var on: Bool
    private var observers: [NSObjectProtocol] = []
    /// The desktops when Mission Control opened, to tell whether one was moved there.
    private var desktopsBefore: [[Int]]?

    init(state: AppState, dock: DockController, windows: WindowControlling = AXWindowControl(),
         notice: @escaping (String) -> Void) {
        self.state = state
        self.dock = dock
        self.windows = windows
        self.notice = notice
        on = false
        observeSetting()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // A moment for the app to bring its window forward.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { self?.activated(app) } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            // Once the new desktop's windows are on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self?.tidyAll() } }
        })
        if state.settings.quickDock { turnOn() }
    }

    /// Mission Control opening and closing (from `MissionControlWatch`).
    func missionControl(showing: Bool) {
        guard on else { return }
        if showing {
            desktopsBefore = Desktops.all()
            return
        }
        let before = desktopsBefore
        desktopsBefore = nil
        // Once it has gone and the window you picked is in front.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, on else { return }
            let now = Desktops.all()
            if let before, !before.isEmpty, !now.isEmpty, before != now {
                log.debug("desktops moved in Mission Control: turning off")
                state.update { $0.quickDock = false }
                notice("Quick Dock turned off")
                return
            }
            // Whatever you picked there is in front: the rest on its desktop swap into the strip.
            tidyAll()
        }
    }

    // MARK: On and off

    /// Settings are one value, so this fires on any change; only the switch itself is acted on.
    private func observeSetting() {
        withObservationTracking {
            _ = state.settings.quickDock
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let wanted = self.state.settings.quickDock
                if wanted != self.on {
                    if wanted { self.turnOn() } else { self.on = false }
                }
                self.observeSetting()
            }
        }
    }

    private func turnOn() {
        guard AccessibilityAccess.isTrusted else { return }
        let groups = showingDesktops()
        if let crowded = groups.map(\.count).max(), crowded > Self.maxWindows {
            log.debug("not turning on: \(crowded) windows on one desktop")
            on = false
            state.update { $0.quickDock = false }
            notice("Quick Dock needs \(Self.maxWindows) or fewer windows per desktop (one has \(crowded))")
            return
        }
        on = true
        groups.forEach { tidy($0) }
    }

    // MARK: Tidying

    /// Every showing desktop, one per display. A desktop with too many windows is left as it is.
    private func tidyAll() {
        guard on, desktopsBefore == nil, Date() > dock.ignoreActivationUntil else { return }
        showingDesktops().forEach { tidy($0) }
    }

    /// An app came forward: its window stays (filling its desktop), the others on that display go to the strip.
    private func activated(_ app: NSRunningApplication) {
        guard on, desktopsBefore == nil, AccessibilityAccess.isTrusted, Date() > dock.ignoreActivationUntil,
              app.processIdentifier != getpid(), app.activationPolicy == .regular,
              let front = windows.frontWindow(pid: app.processIdentifier), AXWindowControl.isStandard(front),
              !windows.isMinimized(front),
              let group = showingDesktops().first(where: { $0.contains(front) }) else { return }
        log.debug("\(app.localizedName ?? "?", privacy: .public) in front")
        tidy(group, front: front)
    }

    /// Keeps `front` (or the frontmost) and sets the rest aside.
    private func tidy(_ group: [ForeignWindow], front: ForeignWindow? = nil) {
        guard let front = front ?? group.first else { return }
        guard group.count <= Self.maxWindows else {
            return log.debug("leaving a desktop with \(group.count) windows alone")
        }
        let others = group.filter { $0 != front }
        if !others.isEmpty { log.debug("setting aside \(others.count)") }
        // Out of its slot on the side first, so the window it swaps with goes into that slot (cards keep their order).
        dock.fill(front)
        others.forEach(dock.setAside)
    }

    /// The ordinary windows on each display's showing desktop, front to back, one list per display.
    private func showingDesktops() -> [[ForeignWindow]] {
        var byScreen: [[ForeignWindow]] = Array(repeating: [], count: NSScreen.screens.count)
        for window in windows.visibleWindows() {
            guard let frame = windows.frame(of: window),
                  let index = NSScreen.screens.indices.max(by: {
                      NSScreen.screens[$0].frame.intersection(frame).overlap < NSScreen.screens[$1].frame.intersection(frame).overlap
                  }) else { continue }
            byScreen[index].append(window)
        }
        return byScreen.filter { !$0.isEmpty }
    }
}

private extension CGRect {
    var overlap: CGFloat { isNull ? 0 : width * height }
}
