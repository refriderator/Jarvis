import JarvisKit
import SwiftUI

/// The closed pill on a display without a hardware notch: the time, the date, the song... one at a time, each
/// fading into the next (`Ticker`, picked in Settings › Display). While a timer runs it shows that instead, its
/// countdown over a bar that empties as it runs down, like the hardware notch's peek.
struct TickerView: View {
    let state: AppState

    var body: some View {
        let height = state.layout.notch.height
        ZStack(alignment: .bottom) {
            Group {
                if let timer = state.timers.first(where: { TimerList.left($0, now: .now) != nil }) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 0) {
                            Text(TimerList.countdown(timer.ends.timeIntervalSince(context.date)))
                                .monospacedDigit()
                                .foregroundStyle(state.skin.accent)
                                .frame(maxHeight: .infinity)
                            TimerBar(left: TimerList.left(timer, now: context.date) ?? 0, accent: state.skin.accent)
                                .padding(.bottom, 1.5)
                        }
                    }
                    .transition(.opacity)
                } else {
                    lines
                        .padding(.bottom, NotchLayout.pillBottom - 1)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.timers.isEmpty)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(state.skin.foreground.opacity(0.85))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 14)
        .frame(width: state.layout.notch.width, height: height)
        .allowsHitTesting(false)
    }

    private var lines: some View {
        let seconds = max(2, state.settings.tickerSeconds)
        return TimelineView(.periodic(from: .now, by: seconds)) { context in
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
            .frame(maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.6), value: lines.isEmpty ? "" : lines[index])
        }
    }
}
