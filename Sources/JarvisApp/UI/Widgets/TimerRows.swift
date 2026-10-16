import JarvisKit
import SwiftUI

/// Running timers, alarms and reminders above "TODAY", like Jarvis Private's hub. A timer counts down;
/// an alarm or reminder shows when it goes off. Hovering a row slides it right and shows an x that cancels it.
struct TimerRows: View {
    let timers: [JarvisTimer]
    let tint: Color
    let accent: Color
    let cancel: (UUID) -> Void
    @State private var hovered: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TimerList.rows(timers, now: context.date)) { row in
                    let isHovered = hovered == row.id
                    ZStack(alignment: .leading) {
                        Button { cancel(row.id) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(tint.opacity(0.6))
                            .opacity(isHovered ? 1 : 0)
                            .help("Cancel")
                        HStack {
                            Text(row.title).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(row.value).monospacedDigit().foregroundStyle(accent).lineLimit(1)
                        }
                        .padding(.leading, isHovered ? 20 : 0)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: NotchLayout.agendaRowHeight)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hovered = row.id } else if hovered == row.id { hovered = nil }
                    }
                    .animation(.easeOut(duration: 0.15), value: isHovered)
                }
            }
        }
    }
}
