import EventKit
import Foundation

/// Where reminders go. The Reminders app's lists sync through iCloud, so a reminder set on the Mac rings on the phone.
@MainActor
public protocol ReminderSource: Sendable {
    /// Saves a reminder; `due` nil for none, `hasTime` false for a day without a time (no alert).
    func add(title: String, due: Date?, hasTime: Bool) throws
}

/// The Reminders app through EventKit, in its default list.
@MainActor
public final class EventKitReminders: ReminderSource {
    private let store = EKEventStore()

    public init() {}

    public func add(title: String, due: Date?, hasTime: Bool) throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            break
        case .notDetermined:
            // Asked now, the first time it's needed; the question is answered again once it's allowed.
            Task { _ = try? await store.requestFullAccessToReminders() }
            throw ChatError("Allow Jarvis to use Reminders in the window that just opened, then ask again.")
        default:
            throw ChatError("Jarvis needs Reminders access. Allow it in Settings › Connections.")
        }
        guard let list = store.defaultCalendarForNewReminders() else { throw ChatError("There's no Reminders list to add to.") }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        if let due {
            let units: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        try store.save(reminder, commit: true)
    }
}
