import AppKit
import JarvisKit

extension NSScreen {
    /// Where Jarvis lives: the Mac's own display (where the notch is), even when an external
    /// monitor is plugged in or set as the main display. Falls back to the main display.
    static var menuBarScreen: NSScreen? { screens.first { $0.isBuiltIn } ?? screens.first }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var notchLayout: NotchLayout {
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        let notch = NotchLayout.notchRect(
            screenFrame: frame, safeAreaTop: safeAreaInsets.top,
            leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea,
            menuBarHeight: menuBarHeight > 0 ? menuBarHeight : 24)
        return NotchLayout(notch: notch)
    }
}
