import JarvisKit
import SwiftUI

/// What shows in the notch's ears while peeking: the next timer's countdown on the left
/// (or a dot), and on the right a waveform that moves while Jarvis listens or talks.
struct PeekView: View {
    let accent: Color
    let voice: VoiceStatus
    let timer: JarvisTimer?

    var body: some View {
        HStack {
            if let timer {
                TimerCountdown(timer: timer)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
            } else {
                Circle()
                    .fill(voice.isListening ? Color.red : accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: voice.isListening ? .red : accent, radius: 4)
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, isActive: voice != .idle)
        }
        .padding(.horizontal, 14)
    }
}

/// "4:32", ticking each second until the timer ends.
struct TimerCountdown: View {
    let timer: JarvisTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(timer.ends.timeIntervalSince(context.date).rounded(.up)))
            Text(left >= 3600 ? String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
                              : String(format: "%d:%02d", left / 60, left % 60))
                .monospacedDigit()
        }
    }
}
