import AppKit
import JarvisKit
import SwiftUI

/// A small notice in the skin's colours that hangs under the notch for a few seconds ("Quick Dock turned off"),
/// on the display the pointer is on: under the notch on the Mac's own display, under the menu bar elsewhere.
/// It never takes clicks, except one that asks (`ask`), which stays until one of its buttons is clicked.
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
        guard place(NoticeView(text: text, skin: state.skin, choices: [])) else { return }
        panel.ignoresMouseEvents = true
        hide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    /// A notice with buttons ("Update", "Later"): it takes clicks and stays until one is clicked, then goes.
    func ask(_ text: String, choices: [(String, () -> Void)]) {
        let choices = choices.map { title, action in
            (title, { [weak self] in
                self?.fadeOut()
                action()
            })
        }
        guard place(NoticeView(text: text, skin: state.skin, choices: choices)) else { return }
        hide?.cancel()
        panel.ignoresMouseEvents = false
    }

    /// Puts the notice under the notch (or the menu bar) of the display the pointer is on and fades it in.
    private func place(_ notice: NoticeView) -> Bool {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? state.notchScreen
        else { return false }
        let view = NSHostingView(rootView: notice)
        let size = view.fittingSize
        // Under the notch where there is one, under the menu bar elsewhere.
        let top = screen == state.notchScreen ? state.layout.notch.minY : screen.visibleFrame.maxY
        panel.contentView = view
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: top - 6 - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        return true
    }

    private func fadeOut() {
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 0 }
    }
}

private struct NoticeView: View {
    let text: String
    let skin: Skin
    /// Buttons after the text, the first one in the accent colour.
    let choices: [(String, () -> Void)]

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
            ForEach(choices.indices, id: \.self) { index in
                let (title, action) = choices[index]
                Button(title, action: action)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .foregroundStyle(index == 0 ? skin.accent : skin.foreground.opacity(0.7))
                    .background((index == 0 ? skin.accent : skin.foreground).opacity(0.15), in: Capsule())
            }
        }
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
