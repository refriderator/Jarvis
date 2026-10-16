import AppKit

/// Notices Mission Control (three-finger swipe up, F3) opening and closing. macOS doesn't announce it, so this
/// looks a few times a second (through Accessibility, which Jarvis already has; well under a millisecond).
@MainActor
final class MissionControlWatch {
    private var timer: Timer?
    private var showing = false
    private let changed: @MainActor (Bool) -> Void

    /// `changed(true)` as Mission Control opens, `changed(false)` once it's gone.
    init(changed: @escaping @MainActor (Bool) -> Void) {
        self.changed = changed
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Self.isShowing()
                guard now != self.showing else { return }
                self.showing = now
                self.changed(now)
            }
        }
    }

    /// While Mission Control is open, the Dock's accessibility tree has a group with the identifier "mc", and at
    /// no other time. (Looking for a full-screen Dock window also caught the Dock just being shown.)
    private static func isShowing() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).contains { child in
            var id: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &id)
            return id as? String == "mc"
        }
    }
}
