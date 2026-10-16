import JarvisKit
import SwiftUI

/// While listening: what Jarvis has heard so far, and how to finish.
struct ListeningView: View {
    let heard: String
    let skin: Skin
    let hotkey: Hotkey
    /// Push-to-hold: let go to send. Toggle: press again, or just stop talking.
    let holding: Bool
    let stopsOnPause: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Listening", systemImage: "waveform")
                .symbolEffect(.variableColor.iterative)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.red)
            Text(heard.isEmpty ? "Go ahead…" : heard)
                .font(.title3.weight(.medium))
                .opacity(heard.isEmpty ? 0.45 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            Text(holding ? "Let go of \(hotkey.text) to send"
                         : stopsOnPause ? "Stops when you pause, or press \(hotkey.text) again"
                                        : "Press \(hotkey.text) or the mic again to send")
                .font(.caption2)
                .opacity(0.45)
        }
        .foregroundStyle(skin.foreground)
        .padding(.horizontal, 6)
    }
}
