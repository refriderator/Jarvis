import Foundation

/// Reads calendar requests in plain code: adding an event (dates via `NSDataDetector`),
/// and questions about the schedule, which get the events added as context for the brain.
public enum CalendarCommand {
    public struct NewEvent: Equatable, Sendable {
        public var title: String
        public var start: Date
        public var end: Date
        public var allDay: Bool
    }

    private static let addPattern =
        #"^\s*(?:please\s+)?(?:add|put|schedule|create|book|make)\b.*\b(?:calendar|event|meeting|appointment)\b"#
    private static let questionPattern =
        #"\b(calendar|schedule|agenda|events?|meetings?|appointments?|classes|lectures?|am i (free|busy)|what('s| is) on|what do i have|anything on)\b"#

    public static func isAdd(_ text: String) -> Bool {
        text.range(of: addPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func isQuestion(_ text: String) -> Bool {
        !isAdd(text) && text.range(of: questionPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "add dentist tomorrow at 3pm to my calendar" -> "Dentist", tomorrow 3–4 PM. Nil if no date is given.
    public static func parseAdd(_ text: String, now: Date = .now) -> NewEvent? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), let date = match.date,
              let dateRange = Range(match.range, in: text) else { return nil }
        let datePhrase = String(text[dateRange])
        let hasTime = datePhrase.range(of: #"\d\s*(:\d\d)?\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|\bnoon\b|\bmidnight\b|\bat \d"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil
        // A time it couldn't read ("evening around six") would become an all-day event: better to ask for a clear one.
        if !hasTime, text.range(of: #"\b(morning|afternoon|evening|tonight|night|around|about|o'?clock|ish)\b"#,
                                options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        var title = text.replacingCharacters(in: dateRange, with: " ")
        for filler in [#"^\s*(please\s+)?(add|put|schedule|create|book|make)\b"#,
                       #"\b(to|on|in|into) my calendar\b"#, #"\bmy calendar\b"#, #"\b(an|a|the) (event|meeting|appointment)\b"#,
                       #"\b(event|meeting|appointment)\b(?=\s*(called|named|for|:))"#, #"\b(called|named)\b"#,
                       #"[.!?]+$"#, #"\b(for|on|at|by|from)\s*$"#, #"^\s*(for|on|at)\b"#] {
            title = title.replacingOccurrences(of: filler, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,:-"))
        if title.isEmpty { title = "Event" }
        title = title.prefix(1).uppercased() + title.dropFirst()

        if !hasTime {
            let day = Calendar.current.startOfDay(for: date)
            return NewEvent(title: title, start: day, end: day.addingTimeInterval(86_400), allDay: true)
        }
        let duration = match.duration > 0 ? match.duration : 3600
        return NewEvent(title: title, start: date, end: date.addingTimeInterval(duration), allDay: false)
    }

    /// Which days a question is about: today and tomorrow, or the week for "this week"/"next week".
    public static func range(for text: String, now: Date = .now) -> (start: Date, end: Date) {
        let day = Calendar.current.startOfDay(for: now)
        let lower = text.lowercased()
        if lower.contains("next week") {
            return (day.addingTimeInterval(7 * 86_400), day.addingTimeInterval(14 * 86_400))
        }
        if lower.contains("week") { return (day, day.addingTimeInterval(7 * 86_400)) }
        return (day, day.addingTimeInterval(2 * 86_400))
    }

    /// The events as a short note to put in front of the question; with `ids`, each event's id too, for calendar_change and calendar_delete.
    public static func context(_ items: [AgendaItem], start: Date, end: Date, ids: Bool = false) -> String {
        guard !items.isEmpty else {
            return "(The user's calendar has no events from \(start.formatted(date: .abbreviated, time: .omitted)) "
                + "to \(end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)).) "
        }
        let lines = items.map { item in
            let day = item.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            let line = item.allDay ? "\(day), all day: \(item.title)"
                : "\(day), \(item.start.formatted(date: .omitted, time: .shortened))–\(item.end.formatted(date: .omitted, time: .shortened)): \(item.title)"
            return ids ? "\(line) (id \(item.id))" : line
        }
        return "(The user's calendar: " + lines.joined(separator: "; ") + ".) "
    }

    /// "Added Dentist, Wednesday at 3:00 PM."
    public static func confirmation(_ item: AgendaItem, verb: String = "Added") -> String {
        "\(verb) \(describe(item))."
    }

    /// "Dentist, Wednesday, October 14 at 3:00 PM", or "Dentist on Wednesday, October 14" for all day.
    public static func describe(_ item: AgendaItem) -> String {
        let day = item.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return item.allDay ? "\(item.title) on \(day)" : "\(item.title), \(day) at \(item.start.formatted(date: .omitted, time: .shortened))"
    }
}
