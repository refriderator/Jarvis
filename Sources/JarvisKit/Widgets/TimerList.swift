import Foundation

/// One running timer or reminder as a row of the open notch.
public struct TimerRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    /// A countdown ("4:59") for a timer, or the time it goes off ("7:00 AM", "7:00 AM tomorrow") otherwise.
    public let value: String
}

/// The rows above "TODAY", soonest first, like Jarvis Private's hub.
public enum TimerList {
    public static func rows(_ timers: [JarvisTimer], now: Date, max: Int = NotchLayout.maxTimerRows) -> [TimerRow] {
        timers.prefix(max).map { timer in
            if timer.alarm || timer.note != nil {
                let title = timer.note.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Reminder"
                return TimerRow(id: timer.id, title: title, value: clock(timer.ends, now: now))
            }
            let title = timer.label.prefix(1).uppercased() + timer.label.dropFirst() + " timer"
            return TimerRow(id: timer.id, title: title, value: countdown(timer.ends.timeIntervalSince(now)))
        }
    }

    /// "4:59", or "1:04:59" past an hour.
    public static func countdown(_ interval: TimeInterval) -> String {
        let left = Swift.max(0, Int(interval.rounded(.up)))
        return left >= 3600 ? String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
            : String(format: "%d:%02d", left / 60, left % 60)
    }

    /// "7:00 AM", "7:00 AM tomorrow" or "7:00 AM Thu".
    static func clock(_ date: Date, now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        return days == 0 ? time : days == 1 ? "\(time) tomorrow" : "\(time) \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }
}
