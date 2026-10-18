import AppKit
import JarvisKit

/// Which displays have an app full screen on the desktop showing (`FullScreen` says why that matters). Going full
/// screen (or leaving it, or ⌘-Tab to a full-screen app) switches desktops, so this looks again then, once the
/// animation is over. Window positions only, through `CGWindowList`: no permission needed.
@MainActor
final class FullScreenWatch {
    private var observers: [NSObjectProtocol] = []
    private(set) var displays: Set<CGDirectDisplayID> = []
    private let changed: @MainActor (Set<CGDirectDisplayID>) -> Void

    init(changed: @escaping @MainActor (Set<CGDirectDisplayID>) -> Void) {
        self.changed = changed
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSoon() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.checkSoon() } })
        check()
    }

    /// Going full screen animates for most of a second: once partway, and again after it's surely done.
    private func checkSoon() {
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.check() }
            }
        }
    }

    private func check() {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        // Layer 0 is apps' ordinary windows: not the menu bar, the Dock or Jarvis's own panels.
        let windows = info.compactMap { window -> CGRect? in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        // Both in CoreGraphics' coordinates (origin top-left of the main display), so no flipping.
        let found = Set(NSScreen.screens.compactMap(\.displayID).filter { id in
            windows.contains { FullScreen.covers($0, display: CGDisplayBounds(id)) }
        })
        guard found != displays else { return }
        displays = found
        changed(found)
    }
}
