import Foundation

/// The reminder fast path: plain wording read by code, no model and no tokens. "remind me in 20 minutes to stretch",
/// "remind me at 8:45 pm to call mom", "remind me to call mom tomorrow", "remind me to buy milk". Each one goes to the
/// Reminders app (`ReminderSource`), so it syncs to the phone and rings there even when the Mac is asleep: why Jarvis
/// had stopped doing reminders with its own timers.
public enum ReminderCommand: Equatable, Sendable {
    /// `when` nil: a reminder with no time, kept in the list.
    case add(title: String, when: SpokenTime?)
    /// Plainly a reminder, but not of what.
    case unclear

    public static let unclearReply = "What should I remind you about? Try \"remind me at 7 pm to call mom\"."

    /// Said instead of "remind me": "ping me at 9 to...", "give me a heads up at 5 to...", "don't let me forget to...".
    static let otherAsks = #"\b(ping|nudge|tell|alert|text) me\b|\bgive me a heads[- ]up\b|\blet me know\b|\bdon'?t let me forget\b"#

    public static func parse(_ text: String) -> ReminderCommand? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: otherAsks, with: "remind me", options: .regularExpression)
        let named = text.lowercased().range(of: #"\bremind me\b|\breminders?\b"#, options: .regularExpression) != nil
        // Any "remind me" or "reminder" is code's: worded loosely ("set me a reminder for..."), it reached the local
        // model, which said it had set one without a tool to do it (10-17).
        let asks = lower.range(of: #"\bremind me\b|\breminders?\b"#, options: .regularExpression) != nil
        guard asks else { return nil }
        // "ping me in 10 min" is a timer, and "tell me a joke" a question: without "remind", only a time and a "to"
        // make it a reminder ("ping me at 9 to call mom"), or "don't let me forget to...".
        if !named, text.lowercased().range(of: #"\bdon'?t let me forget\b"#, options: .regularExpression) == nil,
           SpokenTime.parse(lower) == nil || title(lower) == nil {
            return nil
        }
        // Questions about reminders ("what are my reminders") are for a brain, not an add.
        if lower.range(of: #"^(what|which|show|list|read|do i have|any)\b"#, options: .regularExpression) != nil { return nil }
        guard let title = title(lower) else { return .unclear }
        return .add(title: title, when: SpokenTime.parse(lower))
    }

    /// What it's for: "remind me to X in/at ...", "remind me in/at ... to X", "remind me to X", "reminder to X".
    static func title(_ lower: String) -> String? {
        let patterns = [#"\bremind me to (.+)\s+(?:in|at)\s+\S.*$"#,
                        #"\breminders?\b.*?\b(?:in|at|for)\b.*?\bto (.+)$"#,
                        #"\bremind me\b.*?\b(?:in|at)\b.*?\bto (.+)$"#,
                        #"\bremind me (?:to|about|of) (.+)$"#,
                        #"\breminders? (?:to|for|about) (.+)$"#,
                        #"\bremind me\b.*?\btomorrow\b.*?\bto (.+)$"#]
        let range = NSRange(lower.startIndex..., in: lower)
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: lower, range: range), let found = Range(match.range(at: 1), in: lower) else {
                continue
            }
            let title = lower[found]
                .replacingOccurrences(of: #"\s+(please|tomorrow( morning| afternoon| evening| night)?|tonight|today|this (morning|afternoon|evening))\s*[.!?]*$"#,
                                      with: "", options: .regularExpression)
                // "remind me about the bins at 7": the time, not "in the dryer".
                .replacingOccurrences(of: #"\s+(in|at)\s+(\d|noon|midnight|an? (hour|minute)|half an).*$"#, with: "",
                                      options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
            // "set a reminder for 8:20" says when, not what.
            let onlyTime = title.range(of: #"^((at|for|in|on)\s+)?(\d{1,2}(:\d{2})?\s*(a\.?m\.?|p\.?m\.?)?|noon|midnight|tonight|tomorrow|today)$"#,
                                       options: .regularExpression) != nil
            if !title.isEmpty, !onlyTime, TimerCommand.seconds(in: title).map({ _ in title.split(separator: " ").count > 3 }) ?? true {
                return title
            }
        }
        return nil
    }

    /// "Okay, I'll remind you at 7:00 PM tomorrow to call mom." Said after it's saved.
    public static func confirmation(title: String, due: (date: Date, hasTime: Bool)?, now: Date = .now) -> String {
        guard let due else { return "Added \"\(title)\" to Reminders." }
        let calendar = Calendar.current
        let day = calendar.isDate(due.date, inSameDayAs: now) ? ""
            : calendar.isDateInTomorrow(due.date) ? " tomorrow" : " on " + due.date.formatted(.dateTime.weekday(.wide))
        guard due.hasTime else { return "Okay, \"\(title)\" is in Reminders for\(day.isEmpty ? " today" : day)." }
        return "Okay, I'll remind you at \(due.date.formatted(date: .omitted, time: .shortened))\(day) to \(title)."
    }
}
