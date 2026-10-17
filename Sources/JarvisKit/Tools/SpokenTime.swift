import Foundation

/// When something should happen, as said: "in 20 minutes", "at 8:45 pm", "at 7 tomorrow", "tomorrow". Read by code
/// for reminders and alarms, so no model works out a date.
public enum SpokenTime: Equatable, Sendable {
    /// After a length.
    case after(seconds: Int)
    /// At a clock time: `hour` 0...23, or 1...12 with `pm` nil when it wasn't said (the next one comes first).
    case at(hour: Int, minute: Int, pm: Bool?, tomorrow: Bool)
    /// A day with no time ("tomorrow").
    case day(tomorrow: Bool)

    /// The time said in `text`, or nil when it says none.
    public static func parse(_ text: String) -> SpokenTime? {
        let lower = text.lowercased()
        let tomorrow = lower.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil
        if let clock = clockTime(lower) {
            return .at(hour: clock.hour, minute: clock.minute, pm: clock.pm, tomorrow: tomorrow)
        }
        if lower.range(of: #"\bin\b"#, options: .regularExpression) != nil, let seconds = TimerCommand.seconds(in: lower) {
            return .after(seconds: seconds)
        }
        return tomorrow ? .day(tomorrow: true) : nil
    }

    /// The moment it means, and whether it has a time of day (not just a day).
    public func resolve(now: Date = .now) -> (date: Date, hasTime: Bool)? {
        let calendar = Calendar.current
        switch self {
        case .after(let seconds):
            return (now.addingTimeInterval(TimeInterval(seconds)), true)
        case .day(let tomorrow):
            let start = calendar.startOfDay(for: now)
            return (tomorrow ? calendar.date(byAdding: .day, value: 1, to: start)! : start, false)
        case .at(let hour, let minute, let pm, let tomorrow):
            let hours = pm.map { [$0 ? hour % 12 + 12 : hour % 12] }
                ?? (hour > 12 || hour == 0 ? [hour] : [hour % 12, hour % 12 + 12])
            let after = tomorrow ? calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!) : now
            let next = hours.compactMap {
                calendar.nextDate(after: after.addingTimeInterval(-1), matching: DateComponents(hour: $0, minute: minute, second: 0),
                                  matchingPolicy: .nextTime)
            }.min()
            return next.map { ($0, true) }
        }
    }

    /// "at 8:45 pm", "at 7", "at noon", "for 6:30": hour and minute, and whether it's pm (nil when not said).
    static func clockTime(_ lower: String) -> (hour: Int, minute: Int, pm: Bool?)? {
        if lower.range(of: #"\b(at|for) noon\b"#, options: .regularExpression) != nil { return (12, 0, nil) }
        if lower.range(of: #"\b(at|for) midnight\b"#, options: .regularExpression) != nil { return (0, 0, nil) }
        let pattern = try! NSRegularExpression(pattern: #"\b(?:at|for) (\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?=\s|$|[.,!?])"#)
        guard let match = pattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower), let hour = Int(lower[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
        let half = Range(match.range(at: 3), in: lower).map { lower[$0].hasPrefix("p") }
        // "for 5 minutes" is a length, not 5 o'clock.
        if half == nil, Range(match.range(at: 2), in: lower) == nil,
           lower[Range(match.range, in: lower)!.upperBound...].range(of: #"^\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b"#,
                                                                     options: .regularExpression) != nil {
            return nil
        }
        // "tonight", "this evening", "in the morning" say which half when am/pm wasn't.
        let said = half ?? (lower.range(of: #"\b(tonight|this (afternoon|evening)|in the (afternoon|evening))\b"#, options: .regularExpression) != nil ? true
            : lower.range(of: #"\b(in the morning|tomorrow morning)\b"#, options: .regularExpression) != nil ? false : nil)
        guard minute < 60, said == nil ? (0...23).contains(hour) : (1...12).contains(hour) else { return nil }
        return (hour, minute, hour > 12 ? nil : said)
    }
}
