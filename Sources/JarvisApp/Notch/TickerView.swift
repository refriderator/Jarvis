import JarvisKit
import SwiftUI

/// The closed pill on a display without a hardware notch: the time, the date, the song... one at a time, each
/// fading into the next (`Ticker`, picked in Settings › Display).
struct TickerView: View {
    let state: AppState

    var body: some View {
        let seconds = max(2, state.settings.tickerSeconds)
        TimelineView(.periodic(from: .now, by: seconds)) { context in
            let lines = Ticker.lines(state.settings.tickerItems, now: context.date, nowPlaying: state.nowPlaying,
                                     battery: Battery.current(), weather: state.weather, agenda: state.agenda)
            // Counted from a fixed moment, so it moves on one line every `seconds` whatever redraws it.
            let index = lines.isEmpty ? 0 : Int(context.date.timeIntervalSinceReferenceDate / seconds) % lines.count
            ZStack {
                if !lines.isEmpty {
                    Text(lines[index])
                        .id(lines[index])
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: lines.isEmpty ? "" : lines[index])
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 14)
        .frame(width: state.layout.notch.width, height: state.layout.notch.height)
        .allowsHitTesting(false)
    }
}
