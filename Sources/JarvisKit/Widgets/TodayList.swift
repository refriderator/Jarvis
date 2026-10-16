import Foundation

/// One line of the notch's "TODAY" list.
public struct TodayRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let when: String
    /// Already over, so it is drawn grey.
    public let isPast: Bool
}

/// Today's calendar events, then what's due today from Notion, as the rows the open notch lists.
public enum TodayList {
    /// At most `max` rows. When there are more, rows that are already over go first, earliest first.
    public static func rows(agenda: [AgendaItem], due: [DueItem], now: Date,
                            max: Int = NotchLayout.maxAgendaRows) -> [TodayRow] {
        var rows = agenda.map { TodayRow(id: $0.id, title: $0.title, when: $0.timeText, isPast: $0.isPast(now)) }
            + due.map { TodayRow(id: $0.id, title: $0.title, when: $0.timeText, isPast: $0.isPast(now)) }
        while rows.count > max {
            rows.remove(at: rows.firstIndex { $0.isPast } ?? rows.count - 1)
        }
        return rows
    }
}
