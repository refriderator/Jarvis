import AppKit
import JarvisKit

/// The window dock asked by app name, for the local brain's Mac tools (`MacTools`).
extension DockController {
    /// Sets the named app's front window aside in the strip like Quick Dock does (a full strip makes room).
    /// nil: the app in front.
    func dockWindow(of appName: String?) throws -> String {
        guard AccessibilityAccess.isTrusted else {
            throw ChatError("Moving windows needs Accessibility access: System Settings › Privacy & Security › Accessibility.")
        }
        let app = appName.map(Self.running) ?? frontApp()
        guard let app, let window = windows.frontWindow(pid: app.processIdentifier), AXWindowControl.isStandard(window),
              !windows.isMinimized(window) else {
            throw ChatError(appName.map { "\($0) has no open window to put in the dock." } ?? "No window is in front.")
        }
        setAside(window)
        return "Put \(app.localizedName ?? "the window") in the dock."
    }

    /// Sets every window of the named app that is showing on this desktop aside, for the typed "dock X" command.
    func dockAllWindows(of appName: String) throws -> String {
        guard AccessibilityAccess.isTrusted else {
            throw ChatError("Moving windows needs Accessibility access: System Settings › Privacy & Security › Accessibility.")
        }
        guard let app = Self.running(appName) else { throw ChatError("\(appName) isn't open.") }
        let name = app.localizedName ?? appName
        let shown = windows.visibleWindows().filter { $0.pid == app.processIdentifier && AXWindowControl.isStandard($0) }
        guard !shown.isEmpty else { throw ChatError("\(name) has no open window to put in the dock.") }
        shown.forEach(setAside)
        return shown.count == 1 ? "Put \(name) in the dock." : "Put \(shown.count) \(name) windows in the dock."
    }

    /// Brings the named app's window back out of the strip (or off its side), as clicking it does.
    func undockWindow(of appName: String) throws -> String {
        let held = state.dock.shownApps
        let name = appName.lowercased()
        guard let app = held.first(where: { $0.appName.lowercased() == name })
                ?? held.first(where: { $0.appName.lowercased().hasPrefix(name) }) else {
            let names = held.map(\.appName).joined(separator: ", ")
            throw ChatError("\(appName) isn't in the dock. In it: \(names.isEmpty ? "nothing" : names).")
        }
        restore(app)
        return "Brought \(app.appName) back."
    }

    /// A running app with a Dock icon, by its name or the start of it.
    private static func running(_ name: String) -> NSRunningApplication? {
        let wanted = name.lowercased()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        return apps.first { $0.localizedName?.lowercased() == wanted }
            ?? apps.first { $0.localizedName?.lowercased().hasPrefix(wanted) == true }
    }

    /// The app in front, or the one with the frontmost window when Jarvis itself is in front.
    private func frontApp() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() { return app }
        return windows.visibleWindows().first.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
    }
}
