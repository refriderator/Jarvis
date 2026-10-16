import AppKit

/// An icon that follows the pointer while something comes out of the notch, since the notch's own panel can't
/// draw outside itself. For an app pulled out of the tab it lifts into the pointer, then swells into the
/// window's frame and fades as the real window appears there.
@MainActor
final class DragGhost {
    private let size: CGFloat = 56
    private let imageView = NSImageView()
    private var tracker: Timer?
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .mainMenu + 4
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        panel.contentView = imageView
        return panel
    }()

    func show(_ icon: NSImage, at point: CGPoint, visible: Bool) {
        imageView.image = icon
        panel.setFrame(frame(at: point, side: size), display: false)
        panel.alphaValue = visible ? 0.85 : 0
        panel.orderFrontRegardless()
    }

    /// Grows from the tab's icon size into the pointer, and follows it.
    func lift(_ icon: NSImage, at point: CGPoint) {
        imageView.image = icon
        panel.setFrame(frame(at: point, side: 20), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame(at: point, side: size), display: true)
        }
        tracker?.invalidate()
        tracker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.panel.setFrameOrigin(self.frame(at: NSEvent.mouseLocation, side: self.size).origin)
            }
        }
    }

    /// Swells into `window` (screen frame) and fades out, as the real window appears under it.
    func become(_ window: CGRect) {
        tracker?.invalidate()
        tracker = nil
        let side = min(window.width, window.height) * 0.6
        let target = CGRect(x: window.midX - side / 2, y: window.midY - side / 2, width: side, height: side)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        tracker?.invalidate()
        tracker = nil
        panel.orderOut(nil)
    }

    private func frame(at point: CGPoint, side: CGFloat) -> CGRect {
        CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }
}
