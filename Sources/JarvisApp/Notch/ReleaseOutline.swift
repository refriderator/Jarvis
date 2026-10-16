import AppKit
import JarvisKit
import SwiftUI

/// The dashed outline in the middle of the display while a side card is dragged there: where its window will go,
/// at its size, once it's let go of (`SideDock.released`).
@MainActor
final class ReleaseOutline {
    private let skin: () -> Skin
    private(set) var frame: CGRect?
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Under the dragged card (`CardGhost`), over everything else.
        panel.level = .mainMenu + 3
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }()

    init(skin: @escaping () -> Skin) {
        self.skin = skin
    }

    func show(_ frame: CGRect) {
        guard frame != self.frame else { return }
        let appearing = self.frame == nil
        self.frame = frame
        let skin = skin()
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        panel.contentView = NSHostingView(rootView: shape
            .fill(skin.accent.opacity(0.08))
            .overlay(shape.strokeBorder(skin.accent.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, dash: [9, 7])))
            .frame(width: frame.width, height: frame.height))
        panel.setFrame(frame, display: true)
        guard appearing else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard frame != nil else { return }
        frame = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // Not if it was shown again meanwhile (the card dragged back into the middle).
            MainActor.assumeIsolated { if let self, self.frame == nil { self.panel.orderOut(nil) } }
        }
    }
}
