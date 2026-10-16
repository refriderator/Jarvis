import AppKit
import JarvisKit

extension NSScreen {
    /// Where Jarvis lives: the display picked in Settings › Display (`Settings.notchDisplay`) when it's plugged
    /// in, otherwise the Mac's own display (where the notch is), even when an external monitor is set as the main
    /// display. Falls back to the main display.
    static func notchScreen(_ chosen: String) -> NSScreen? {
        screens.first { !chosen.isEmpty && $0.key == chosen } ?? screens.first { $0.isBuiltIn } ?? screens.first
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stays the same for a display across restarts and replugging, unlike `displayID`.
    var key: String {
        guard let id = displayID else { return "" }
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// The display's name for menus: "Built-in Display" for the Mac's own.
    var title: String { isBuiltIn ? "Built-in Display" : localizedName }

    var notchLayout: NotchLayout {
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        let notch = NotchLayout.notchRect(
            screenFrame: frame, safeAreaTop: safeAreaInsets.top,
            leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea,
            menuBarHeight: menuBarHeight > 0 ? menuBarHeight : 24)
        var layout = NotchLayout(notch: notch)
        layout.isPill = safeAreaInsets.top == 0
        return layout
    }
}

extension AppState {
    /// The display the notch is on now.
    var notchScreen: NSScreen? { NSScreen.notchScreen(settings.notchDisplay) }
}
