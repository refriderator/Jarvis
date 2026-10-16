import AppKit
import SwiftUI

/// Shows one SwiftUI window (Settings, Welcome), reusing it if already open.
/// Jarvis has no Dock icon, so the app is activated to bring the window forward.
@MainActor
final class WindowPresenter {
    private var window: NSWindow?

    func show<Content: View>(title: String, content: () -> Content) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { note in
                let closing = note.object as? NSWindow
                MainActor.assumeIsolated { WindowPresenter.backToAccessory(unlessOtherThan: closing) }
            }
            self.window = window
        }
        // An accessory app has no Dock icon and is missing from Cmd-Tab.
        // Act as a normal app while a window is open so it can be switched to.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window, !window.isVisible { Self.center(window) }
        window?.makeKeyAndOrderFront(nil)
    }

    /// Centered on the display the pointer is on, not wherever macOS would pick.
    private static func center(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { return window.center() }
        let area = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2 + area.height / 8))
    }

    func close() {
        window?.close()
    }

    /// Back to menu-bar-only (no Dock icon) once the closing window was the last titled one.
    private static func backToAccessory(unlessOtherThan closing: NSWindow?) {
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !othersOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
