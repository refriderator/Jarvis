import Foundation

/// A running timer.
public struct JarvisTimer: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let seconds: Int
    public let ends: Date
    /// What a reminder is for, e.g. "call Mom".
    public let note: String?
    /// Set for a clock time ("7:00 AM") rather than a length, so the list shows the time instead of a countdown.
    public let alarm: Bool

    public init(id: UUID = UUID(), seconds: Int, ends: Date, note: String? = nil, alarm: Bool = false) {
        self.id = id
        self.seconds = seconds
        self.ends = ends
        self.note = note
        self.alarm = alarm
    }

    /// "5 minute", "1 hour 30 minute"
    public var label: String {
        TimerCommand.describe(seconds).replacingOccurrences(of: #"(hour|minute|second)s"#, with: "$1", options: .regularExpression)
    }
}

/// The timer fast path: plain wording read by code, no model and no tokens. Jarvis has timers and reminders only:
/// "timer 10 minutes", "remind me in 20 minutes to stretch", "remind me at 8:45 pm to call mom". Alarms are
/// refused with a pointer to those (it can't wake a sleeping Mac or reach a phone).
public enum TimerCommand: Equatable, Sendable {
    /// After a length; `note` for a reminder.
    case start(seconds: Int, note: String? = nil)
    /// At a clock time: `hour` 0...23, or 1...12 with `pm` nil when it wasn't said (the next one comes first).
    case at(hour: Int, minute: Int, pm: Bool?, note: String?)
    case cancelAll
    case status
    /// "Set an alarm", "wake me up at 7".
    case noAlarms

    private static let numberWords = ["a": 1.0, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                      "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20,
                                      "thirty": 30, "forty": 40, "forty five": 45, "fifty": 50, "sixty": 60, "ninety": 90]

    private static let amount = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?|forty five|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty|fifty|sixty|ninety)[\s-]*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#)

    public static func parse(_ text: String) -> TimerCommand? {
        let lower = text.lowercased()
        if lower.range(of: #"\b(alarms?|wake me)\b"#, options: .regularExpression) != nil {
            // Cancelling or asking about one is a timer question; anything else asks for an alarm.
            if lower.range(of: #"\b(cancel|stop|clear|delete|remove|how (much|long)|left)\b"#, options: .regularExpression) == nil {
                return .noAlarms
            }
        }
        let mentionsTimer = lower.range(of: #"\b(timers?|countdown|alarms?|reminders?)\b"#, options: .regularExpression) != nil
        let remind = lower.range(of: #"\bremind me\b"#, options: .regularExpression) != nil
        guard mentionsTimer || remind else { return nil }
        // "Remind me at 5 to cancel the gym" is a reminder, not a cancel.
        if !remind, lower.range(of: #"\b(cancel|stop|clear|delete|remove)\b"#, options: .regularExpression) != nil {
            return .cancelAll
        }
        if !remind, lower.range(of: #"\b(how (much|long)|time left|remaining|left on)\b"#, options: .regularExpression) != nil {
            return .status
        }
        let note = remind ? self.note(lower) : nil
        if remind, let clock = clockTime(lower) {
            return .at(hour: clock.hour, minute: clock.minute, pm: clock.pm, note: note)
        }
        if remind, lower.range(of: #"\bremind me\b.*\bin\b"#, options: .regularExpression) == nil { return nil }
        var seconds = 0.0
        // Taken out first, or "an hour" inside it would count too.
        let half = #"\bhalf an? hour\b"#
        if lower.range(of: half, options: .regularExpression) != nil { seconds += 1800 }
        let spoken = lower.replacingOccurrences(of: half, with: " ", options: .regularExpression)
        let range = NSRange(spoken.startIndex..., in: spoken)
        for match in amount.matches(in: spoken, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: spoken),
                  let unitRange = Range(match.range(at: 2), in: spoken) else { continue }
            let word = String(spoken[numberRange])
            guard let number = Double(word) ?? numberWords[word] else { continue }
            let unit = spoken[unitRange]
            let size: Double = unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1
            seconds += number * size
            // "an hour and a half"
            if spoken[unitRange.upperBound...].hasPrefix(" and a half") { seconds += size / 2 }
        }
        guard seconds >= 1 else { return nil }
        return .start(seconds: Int(seconds.rounded()), note: note)
    }

    /// "at 8:45 pm", "at 7", "at noon": hour and minute, and whether it's pm (nil when not said).
    private static func clockTime(_ lower: String) -> (hour: Int, minute: Int, pm: Bool?)? {
        if lower.range(of: #"\bat noon\b"#, options: .regularExpression) != nil { return (12, 0, nil) }
        if lower.range(of: #"\bat midnight\b"#, options: .regularExpression) != nil { return (0, 0, nil) }
        let pattern = try! NSRegularExpression(pattern: #"\bat (\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?(?=\s|$|[.,!?])"#)
        guard let match = pattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower), let hour = Int(lower[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: lower).flatMap { Int(lower[$0]) } ?? 0
        let half = Range(match.range(at: 3), in: lower).map { lower[$0].hasPrefix("p") }
        // "tonight", "this evening", "in the morning" say which half when am/pm wasn't.
        let said = half ?? (lower.range(of: #"\b(tonight|this (afternoon|evening)|in the (afternoon|evening))\b"#, options: .regularExpression) != nil ? true
            : lower.range(of: #"\bin the morning\b"#, options: .regularExpression) != nil ? false : nil)
        guard minute < 60, said == nil ? (0...23).contains(hour) : (1...12).contains(hour) else { return nil }
        return (hour, minute, hour > 12 ? nil : said)
    }

    /// What a reminder is for: "remind me to X in/at ..." or "remind me in/at ... to X".
    private static func note(_ lower: String) -> String? {
        let first = try! NSRegularExpression(pattern: #"\bremind me to (.+)\s+(?:in|at)\s"#)
        let last = try! NSRegularExpression(pattern: #"\bremind me\b.*?\b(?:in|at)\b.*?\bto (.+)$"#)
        let range = NSRange(lower.startIndex..., in: lower)
        for regex in [first, last] {
            if let match = regex.firstMatch(in: lower, range: range), let found = Range(match.range(at: 1), in: lower) {
                let note = lower[found].trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
                    .replacingOccurrences(of: #"\s+please$"#, with: "", options: .regularExpression)
                return note.isEmpty ? nil : note
            }
        }
        return nil
    }

    /// "5 minutes", "1 hour, 30 minutes"
    public static func describe(_ seconds: Int, unitStyle: DateComponentsFormatter.UnitsStyle = .full) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = unitStyle
        return (formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) seconds").replacingOccurrences(of: ",", with: "")
    }
}
