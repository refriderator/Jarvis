import EventKit
import Foundation

/// One calendar event, simplified for the notch and for prompts.
public struct AgendaItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
    }

    /// Already over today, so the notch greys it out.
    public func isPast(_ now: Date) -> Bool { !allDay && end <= now }

    /// "9 AM", "9:30 AM" or "All day"
    public var timeText: String {
        guard !allDay else { return "All day" }
        let minutes = Calendar.current.component(.minute, from: start)
        return start.formatted(minutes == 0 ? .dateTime.hour() : .dateTime.hour().minute())
    }
}

/// The user's calendars. Nil from `events` means no access.
@MainActor
public protocol CalendarSource: Sendable {
    func events(from start: Date, to end: Date) -> [AgendaItem]?
    func add(title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem
    /// One event by its id, or nil if there is none (or no access).
    func event(id: String) -> AgendaItem?
    /// Replaces one event's title and times (only this occurrence of a repeating event).
    func change(id: String, title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem
    /// Deletes one event (only this occurrence of a repeating event).
    func delete(id: String) throws
}

/// Calendar.app's calendars through EventKit, so Google and iCloud calendars added there count too.
@MainActor
public final class EventKitCalendar: CalendarSource {
    private let store = EKEventStore()

    public init() {}

    private var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    public func events(from start: Date, to end: Date) -> [AgendaItem]? {
        guard hasAccess else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(Self.item)
    }

    private static func item(_ event: EKEvent) -> AgendaItem {
        AgendaItem(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "Untitled",
                   start: event.startDate, end: event.endDate, allDay: event.isAllDay)
    }

    /// The accounts Calendar.app has, with their calendars: "Google (you@gmail.com): Classes, Personal".
    /// Empty without access.
    public static func accounts() -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendars = EKEventStore().calendars(for: .event)
        let bySource = Dictionary(grouping: calendars) { $0.source?.title ?? "On My Mac" }
        return bySource.keys.sorted().map { source in
            let names = bySource[source, default: []].map(\.title).sorted().joined(separator: ", ")
            return "\(source): \(names)"
        }
    }

    /// System Settings › Internet Accounts, where Google, iCloud, Exchange and others are added to Calendar.app.
    public static let addAccountURL = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!

    public func add(title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        guard hasAccess else { throw ChatError("Jarvis needs Calendar access. Allow it in Settings › Connections.") }
        guard let calendar = store.defaultCalendarForNewEvents else { throw ChatError("There's no calendar to add to.") }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        try store.save(event, span: .thisEvent)
        return AgendaItem(id: event.eventIdentifier ?? UUID().uuidString, title: title, start: start, end: end, allDay: allDay)
    }

    public func event(id: String) -> AgendaItem? {
        guard hasAccess, let event = store.event(withIdentifier: id) else { return nil }
        return Self.item(event)
    }

    public func change(id: String, title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        let event = try stored(id)
        event.title = title
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = end
        try store.save(event, span: .thisEvent)
        return Self.item(event)
    }

    public func delete(id: String) throws {
        try store.remove(try stored(id), span: .thisEvent)
    }

    private func stored(_ id: String) throws -> EKEvent {
        guard hasAccess else { throw ChatError("Jarvis needs Calendar access. Allow it in Settings › Connections.") }
        guard let event = store.event(withIdentifier: id) else { throw ChatError("No event has id \(id). Call calendar_list for real ids.") }
        return event
    }
}
