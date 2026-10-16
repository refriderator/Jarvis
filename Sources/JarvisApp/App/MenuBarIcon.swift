import AppKit

/// The menu-bar icon: the waveform, with a small dot in its bottom-right corner while Quick Dock is on (the open
/// notch has no room left of the hardware notch to say so).
enum MenuBarIcon {
    static func image(quickDock: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let wave = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jarvis")?
            .withSymbolConfiguration(config) else { return NSImage() }
        guard quickDock else {
            wave.isTemplate = true
            return wave
        }
        let dot: CGFloat = 5
        let size = CGSize(width: wave.size.width + dot / 2, height: wave.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            wave.draw(in: CGRect(origin: .zero, size: wave.size))
            // A clear ring around the dot, so it reads apart from the waveform's bars.
            let ring = CGRect(x: size.width - dot - 1.5, y: -1.5, width: dot + 3, height: dot + 3)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: ring).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Jarvis, Quick Dock on"
        return image
    }
}
