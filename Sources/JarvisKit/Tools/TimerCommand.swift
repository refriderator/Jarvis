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

/// The timer fast path: plain wording read by code, no model and no tokens ("timer 10 minutes", "an hour and a half
/// timer"). Timers live in Jarvis; reminders go to the Reminders app (`ReminderCommand`) and alarms to the Clock app
/// through a shortcut (`AlarmCommand`), since a Jarvis timer can't wake a sleeping Mac or reach a phone.
public enum TimerCommand: Equatable, Sendable {
    case start(seconds: Int)
    case cancelAll
    case status

    private static let numberWords = ["a": 1.0, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                      "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20,
                                      "thirty": 30, "forty": 40, "forty five": 45, "fifty": 50, "sixty": 60, "ninety": 90]

    private static let amount = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?|forty five|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty|fifty|sixty|ninety)[\s-]*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#)

    public static func parse(_ text: String) -> TimerCommand? {
        let lower = text.lowercased()
        guard lower.range(of: #"\b(timers?|countdown)\b"#, options: .regularExpression) != nil else { return nil }
        if lower.range(of: #"\b(cancel|stop|clear|delete|remove)\b"#, options: .regularExpression) != nil { return .cancelAll }
        if lower.range(of: #"\b(how (much|long)|time left|remaining|left on)\b"#, options: .regularExpression) != nil {
            return .status
        }
        return seconds(in: lower).map { .start(seconds: $0) }
    }

    /// How long a spoken length is: "10 minutes", "1 hour 30 min", "half an hour", "an hour and a half". Nil when it
    /// says none. The local brain's timer tool takes the length as said and reads it with this, so the model only
    /// copies words: worked out by Qwen, "an hour and a half" came out as 3600 seconds.
    public static func seconds(in text: String) -> Int? {
        let lower = text.lowercased()
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
        return seconds >= 1 ? Int(seconds.rounded()) : nil
    }

    /// "5 minutes", "1 hour, 30 minutes"
    public static func describe(_ seconds: Int, unitStyle: DateComponentsFormatter.UnitsStyle = .full) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = unitStyle
        return (formatter.string(from: TimeInterval(seconds)) ?? "\(seconds) seconds").replacingOccurrences(of: ",", with: "")
    }
}
