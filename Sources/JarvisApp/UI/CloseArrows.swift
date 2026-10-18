import SwiftUI

/// Two up chevrons at the top centre of the open dropdown, where the hardware notch would be. Only on a pill
/// (a display without a notch): there that spot is empty, and with hover to open, brushing the top of the screen
/// opens the dropdown by accident, so this puts it away without reaching for Esc.
struct CloseArrows: View {
    let tint: Color
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            // Two stacked chevrons rather than a "chevron.up.2" symbol, which not every macOS has.
            VStack(spacing: -4) {
                Image(systemName: "chevron.up")
                Image(systemName: "chevron.up")
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint.opacity(0.6))
            // Bigger to hit than to see.
            .frame(width: 44, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}
