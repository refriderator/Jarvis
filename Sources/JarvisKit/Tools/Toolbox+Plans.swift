import Foundation

/// Plans and time questions ("what's on Tuesday", "am I free Friday", "what's due this week", "when's my exam") get
/// both of the user's sources in front of them: the calendar's events and Notion's due items for the days asked
/// about. Worded one way, a question used to see only the calendar, worded another only Notion, so the answer
/// changed with the wording. Decided by code (word lists), never a model.
extension Toolbox {
    public func isPlans(_ text: String) -> Bool {
        guard !CalendarCommand.isAdd(text) else { return false }
        return CalendarCommand.isQuestion(text)
            || text.range(of: Self.notionWords, options: [.regularExpression, .caseInsensitive]) != nil
            || text.range(of: Self.planWords, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Am I free Friday", "my plans this weekend", "anything on tomorrow": time asked about without calendar words.
    static let planWords = #"\b(am i (free|busy)|free time|(my|any) plans|anything (on|for|due))\b"#

    /// The calendar's events and Notion's due items for the days asked about, as notes before the question. Empty
    /// for any other question. When Notion can't be reached, its part is left out and Claude still has its tools.
    public func planContext(for text: String, now: Date = .now) async -> String {
        guard isPlans(text) else { return "" }
        let range = CalendarCommand.range(for: text, now: now)
        var notes = ""
        if let calendar {
            notes += calendar.events(from: range.start, to: range.end)
                .map { CalendarCommand.context($0, start: range.start, end: range.end) }
                ?? "(Jarvis can't see the user's calendar: Calendar access is off.) "
        }
        if let api = notionAPI() {
            let days = max(1, Int(range.end.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 86_400 + 0.5))
            if let items = try? await api.dueItems(days: days, now: now) {
                notes += Self.dueNote(items.filter { $0.due >= range.start && $0.due < range.end },
                                      start: range.start, end: range.end, now: now)
            }
        }
        return notes
    }

    /// "(Due in Notion from Oct 20 to Oct 20: Exams: ... Coursework: ...) "
    static func dueNote(_ items: [DueItem], start: Date, end: Date, now: Date) -> String {
        let span = "from \(start.formatted(date: .abbreviated, time: .omitted)) to "
            + end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)
        guard !items.isEmpty else { return "(Nothing is due in Notion \(span).) " }
        let days = max(1, Int(end.timeIntervalSince(start) / 86_400))
        return "(Due in Notion \(span):\n" + NotionAPI.grouped(items, days: days, now: now) + ") "
    }
}
