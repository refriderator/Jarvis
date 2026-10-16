import ApplicationServices
import Foundation

/// Which desktop (Space) a window is on, for the log. macOS has no public API for desktops, so this reads
/// SkyLight's private calls through `dlsym`; it only ever reads (moving another app's window to a desktop is
/// blocked for apps like Jarvis), and every lookup fails soft to nil.
public enum Desktops {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    private typealias DisplaySpace = @convention(c) (Int32, CFString) -> UInt64
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias WindowOfElement = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError

    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer?, as: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
    }

    private static var skyLight: UnsafeMutableRawPointer? {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    }

    /// The desktop showing now on `display` (each display has its own with "Displays have separate Spaces").
    /// Without one, or if that can't be told, the desktop of whichever display was used last, which with an
    /// external monitor is often not the notch's.
    public static func active(on display: CGDirectDisplayID? = nil) -> Int? {
        let sky = skyLight
        guard let main = symbol("SLSMainConnectionID", in: sky, as: MainConnection.self) else { return nil }
        if let display, let current = symbol("SLSManagedDisplayGetCurrentSpace", in: sky, as: DisplaySpace.self),
           let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
           let name = CFUUIDCreateString(nil, uuid) {
            let id = current(main(), name)
            if id != 0 { return Int(id) }
        }
        guard let active = symbol("SLSGetActiveSpace", in: sky, as: ActiveSpace.self) else { return nil }
        let id = active(main())
        return id == 0 ? nil : Int(id)
    }

    /// The desktops a window is on (one, unless it's on every desktop).
    public static func of(_ window: AXUIElement) -> [Int] {
        let sky = skyLight
        guard let main = symbol("SLSMainConnectionID", in: sky, as: MainConnection.self),
              let spaces = symbol("SLSCopySpacesForWindows", in: sky, as: SpacesForWindows.self),
              let id = windowID(of: window) else { return [] }
        return spaces(main(), 7, [id] as CFArray)?.takeRetainedValue() as? [Int] ?? []
    }

    /// The WindowServer's number for a window (what screen capture and `CGWindowList` call it).
    public static func windowID(of window: AXUIElement) -> UInt32? {
        guard let get = symbol("_AXUIElementGetWindow", in: dlopen(nil, RTLD_NOW), as: WindowOfElement.self)
        else { return nil }
        var id: UInt32 = 0
        return get(window, &id) == .success ? id : nil
    }

    /// Every desktop, display by display, in Mission Control's order. Moving a desktop in Mission Control (or
    /// adding or closing one) changes it; switching desktops doesn't. Empty if it can't be told.
    public static func all() -> [[Int]] {
        typealias DisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        let sky = skyLight
        guard let main = symbol("SLSMainConnectionID", in: sky, as: MainConnection.self),
              let copy = symbol("SLSCopyManagedDisplaySpaces", in: sky, as: DisplaySpaces.self),
              let displays = copy(main())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return displays.map { display in
            (display["Spaces"] as? [[String: Any]] ?? []).compactMap { ($0["id64"] ?? $0["ManagedSpaceID"]) as? Int }
        }
    }

    /// "window on [desktops], showing desktop N", for the log.
    public static func describe(_ window: AXUIElement) -> String? {
        guard let active = active() else { return nil }
        return "window on \(of(window)), showing \(active)"
    }
}
