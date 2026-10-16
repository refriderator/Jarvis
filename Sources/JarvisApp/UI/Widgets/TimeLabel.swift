import SwiftUI

/// Big time with the date under it, ticking each minute.
struct TimeLabel: View {
    let tint: Color

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.5))
            }
        }
    }
}
