import AppKit
import ApplicationServices

/// A window of another app, reached through Accessibility.
public struct ForeignWindow: Equatable {
    public let element: AXUIElement
    public let pid: Int32

    public static func == (a: ForeignWindow, b: ForeignWindow) -> Bool {
        a.pid == b.pid && CFEqual(a.element, b.element)
    }
}

/// Moves, sizes, minimizes and closes other apps' windows. Frames are screen coordinates, AppKit style.
@MainActor
public protocol WindowControlling {
    /// The window under a point, if it belongs to another app.
    func window(at point: CGPoint) -> ForeignWindow?
    /// nil once the window has closed.
    func frame(of window: ForeignWindow) -> CGRect?
    /// Returns the frame it really got: apps can refuse to go below their minimum size.
    @discardableResult func setFrame(_ frame: CGRect, of window: ForeignWindow) -> CGRect?
    /// Brings it in front of other windows (and its app forward, when `activate`). Activating makes it the
    /// app's main window first: macOS switches to whichever desktop holds the app's main window, so otherwise it
    /// can jump back to a desktop where the app has other windows.
    func raise(_ window: ForeignWindow, activate: Bool)
    /// Minimized windows sit in the Dock and belong to no desktop: restored, they open on the current one.
    func setMinimized(_ minimized: Bool, _ window: ForeignWindow)
    func isMinimized(_ window: ForeignWindow) -> Bool
    func close(_ window: ForeignWindow)
    /// Hides or shows the whole app, like ⌘H: instant, with no animation.
    func setAppHidden(_ hidden: Bool, pid: Int32)
    /// The app's frontmost window.
    func frontWindow(pid: Int32) -> ForeignWindow?
    /// A browser's floating Picture in Picture video window, if one is open.
    func pictureInPicture() -> ForeignWindow?
    /// Other apps' ordinary windows showing on this desktop, front to back.
    func visibleWindows() -> [ForeignWindow]
}

/// Accessibility (the same API window managers like Rectangle use). Needs the user to allow Jarvis in
/// System Settings › Privacy & Security › Accessibility; without it every call finds nothing.
@MainActor
public struct AXWindowControl: WindowControlling {
    public init() {
        // Every call waits for the other app to answer, on the main thread; by default up to about 6 s for a busy
        // or hung app, which froze the notch and the side cards' animation. Capped for every element at once.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.timeout)
    }

    /// The longest any Accessibility call may wait for an app.
    public static let timeout: Float = 0.5

    public func window(at point: CGPoint) -> ForeignWindow? {
        // Only ordinary windows: panels and dialogs are left alone, and so are floating windows like Picture in
        // Picture (Firefox calls its video window a standard one, so it's told apart by floating above the rest).
        guard let window = anyWindow(at: point),
              Self.string(window.element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String,
              Self.topLayer(at: ScreenSpace.flip(point, mainHeight: Self.mainHeight), pid: window.pid) == 0
        else { return nil }
        return window
    }

    /// The window layer of `pid`'s topmost window under `p` (top-left based): 0 for ordinary windows, more for
    /// floating ones.
    private static func topLayer(at p: CGPoint, pid: Int32) -> Int? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.first { info in
            info[kCGWindowOwnerPID as String] as? Int32 == pid
                && (info[kCGWindowBounds as String] as? NSDictionary)
                    .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }?.contains(p) == true
        }?[kCGWindowLayer as String] as? Int
    }

    private func anyWindow(at point: CGPoint) -> ForeignWindow? {
        let p = ScreenSpace.flip(point, mainHeight: Self.mainHeight)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard pid != getpid() else { return nil }
        // The hit is usually something inside the window (the title bar, a button); climb to the window.
        if Self.string(hit, kAXRoleAttribute) == kAXWindowRole as String {
            return ForeignWindow(element: hit, pid: pid)
        }
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            return ForeignWindow(element: window as! AXUIElement, pid: pid)
        }
        // Title bars often don't say which window they belong to: ask the WindowServer what's under the point
        // instead, then find that app's window with the same frame.
        return windowServerWindow(at: p)
    }

    /// `p` is top-left based. The topmost normal window (layer 0) under it, matched to its AX window.
    private func windowServerWindow(at p: CGPoint) -> ForeignWindow? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.contains(p) else { continue }
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &raw)
            let target = ScreenSpace.flip(bounds, mainHeight: Self.mainHeight)
            return (raw as? [AXUIElement] ?? [])
                .map { ForeignWindow(element: $0, pid: pid) }
                .first { frame(of: $0).map { abs($0.minX - target.minX) + abs($0.maxY - target.maxY) < 4 } ?? false }
        }
        return nil
    }

    public func frame(of window: ForeignWindow) -> CGRect? {
        guard let origin: CGPoint = Self.value(window.element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = Self.value(window.element, kAXSizeAttribute, .cgSize) else { return nil }
        return ScreenSpace.flip(CGRect(origin: origin, size: size), mainHeight: Self.mainHeight)
    }

    @discardableResult
    public func setFrame(_ frame: CGRect, of window: ForeignWindow) -> CGRect? {
        let flipped = ScreenSpace.flip(frame, mainHeight: Self.mainHeight)
        // Size, move, size again: a window that doesn't fit where it is yet gets clamped on the first size.
        Self.set(window.element, kAXSizeAttribute, flipped.size, .cgSize)
        Self.set(window.element, kAXPositionAttribute, flipped.origin, .cgPoint)
        Self.set(window.element, kAXSizeAttribute, flipped.size, .cgSize)
        return self.frame(of: window)
    }

    public func raise(_ window: ForeignWindow, activate: Bool) {
        if activate { AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue) }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if activate { NSRunningApplication(processIdentifier: window.pid)?.activate() }
    }

    public func setMinimized(_ minimized: Bool, _ window: ForeignWindow) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, minimized as CFBoolean)
    }

    public func setAppHidden(_ hidden: Bool, pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        _ = hidden ? app.hide() : app.unhide()
    }

    public func isMinimized(_ window: ForeignWindow) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window.element, kAXMinimizedAttribute as CFString, &value)
        return value as? Bool ?? false
    }

    /// Whether it's an ordinary window (not a panel, dialog or floating window).
    public static func isStandard(_ window: ForeignWindow) -> Bool {
        string(window.element, kAXSubroleAttribute) == kAXStandardWindowSubrole as String
    }

    public func close(_ window: ForeignWindow) {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    public func visibleWindows() -> [ForeignWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var found: [ForeignWindow] = []
        var byApp: [Int32: [ForeignWindow]] = [:]
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != getpid(),
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  bounds.width > 80, bounds.height > 60 else { continue }
            if byApp[pid] == nil {
                var raw: CFTypeRef?
                AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &raw)
                byApp[pid] = (raw as? [AXUIElement] ?? []).map { ForeignWindow(element: $0, pid: pid) }
            }
            // Match the WindowServer's window to its Accessibility one by frame.
            let target = ScreenSpace.flip(bounds, mainHeight: Self.mainHeight)
            if let window = byApp[pid]?.first(where: { candidate in
                   frame(of: candidate).map { abs($0.minX - target.minX) + abs($0.maxY - target.maxY) + abs($0.width - target.width) < 6 } ?? false
               }), Self.isStandard(window), !found.contains(window) {
                found.append(window)
            }
        }
        return found
    }

    public func pictureInPicture() -> ForeignWindow? {
        // Window titles in the WindowServer's list need Screen Recording, so it's only used to find apps with a
        // floating window; Accessibility (which Jarvis has) then reads those windows' titles.
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let floating = Set(list.compactMap { info -> Int32? in
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer > 0, layer < Int(CGWindowLevelForKey(.mainMenuWindow)),
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != getpid() else { return nil }
            return pid
        })
        for pid in floating {
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &raw)
            // Firefox: "Picture-in-Picture"; Chrome: "Picture in Picture".
            if let window = (raw as? [AXUIElement] ?? []).first(where: {
                (Self.string($0, kAXTitleAttribute) ?? "").lowercased().replacingOccurrences(of: "-", with: " ")
                    == "picture in picture"
            }) {
                return ForeignWindow(element: window, pid: pid)
            }
        }
        return nil
    }

    public func frontWindow(pid: Int32) -> ForeignWindow? {
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString,
                                            &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return ForeignWindow(element: window as! AXUIElement, pid: pid)
    }

    // MARK: AX plumbing

    /// Accessibility measures from the top of the main display (the one with the menu bar in System Settings).
    private static var mainHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String, _ type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        return AXValueGetValue(raw as! AXValue, type, pointer) ? pointer.pointee : nil
    }

    private static func set<T: BitwiseCopyable>(_ element: AXUIElement, _ attribute: String, _ value: T, _ type: AXValueType) {
        var value = value
        guard let wrapped = AXValueCreate(type, &value) else { return }
        AXUIElementSetAttributeValue(element, attribute as CFString, wrapped)
    }
}

/// The folder the front Finder window shows. Accessibility doesn't say, so this asks Finder (Automation
/// permission, asked once). nil for windows with no folder (Recents, search results).
public enum FinderFolder {
    public static let bundleID = "com.apple.finder"

    public static func front() -> URL? {
        let script = NSAppleScript(source: """
            tell application "Finder" to get POSIX path of (target of front Finder window as alias)
            """)
        var error: NSDictionary?
        guard let path = script?.executeAndReturnError(&error).stringValue, error == nil else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}

/// Whether Jarvis may use Accessibility, and asking for it.
public enum AccessibilityAccess {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "allow Jarvis to control this computer" prompt (or does nothing if already allowed).
    public static func request() {
        let prompt = "AXTrustedCheckOptionPrompt" as CFString
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }
}
