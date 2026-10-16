import JarvisKit
import SwiftUI

/// "TODAY": today's calendar events, then only what's due today from Notion, in one list like Jarvis Private.
/// Rows whose time has passed are greyed out.
struct AgendaList: View {
    let agenda: [AgendaItem]
    let due: [DueItem]
    let tint: Color

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint.opacity(0.45))
                    .frame(height: NotchLayout.agendaHeaderHeight, alignment: .leading)
                ForEach(TodayList.rows(agenda: agenda, due: due, now: context.date)) { row in
                    HStack {
                        Text(row.title).lineLimit(1)
                        Spacer(minLength: 12)
                        Text(row.when).foregroundStyle(tint.opacity(row.isPast ? 0.25 : 0.5)).lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint.opacity(row.isPast ? 0.3 : 1))
                    .frame(height: NotchLayout.agendaRowHeight)
                }
            }
        }
    }
}
