import AppKit
import JarvisKit
import SwiftUI

/// A small notice in the skin's colours that hangs under the notch for a few seconds ("Quick Dock turned off"),
/// on the display the pointer is on: under the notch on the Mac's own display, under the menu bar elsewhere.
/// It never takes clicks.
@MainActor
final class NoticePanel {
    private let state: AppState
    private let panel = NotchPanel()
    private var hide: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
    }

    func show(_ text: String) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.menuBarScreen
        else { return }
        let view = NSHostingView(rootView: NoticeView(text: text, skin: state.skin))
        let size = view.fittingSize
        // Under the notch where there is one, under the menu bar elsewhere.
        let top = screen == NSScreen.menuBarScreen ? state.layout.notch.minY : screen.visibleFrame.maxY
        panel.contentView = view
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: top - 6 - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.35; self.panel.animator().alphaValue = 0 }
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }
}

private struct NoticeView: View {
    let text: String
    let skin: Skin

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .fontDesign(skin.fontDesign)
            .foregroundStyle(skin.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(skin.background.opacity(skin.material == .glass ? 0.85 : skin.backgroundOpacity), in: Capsule())
            .overlay(Capsule().strokeBorder(skin.border ?? skin.accent.opacity(0.5), lineWidth: 1))
            .fixedSize()
    }
}
