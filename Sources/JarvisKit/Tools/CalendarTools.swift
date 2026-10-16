import Foundation

/// The calendar as tools for the local brain. Dates and ids are checked here, not trusted: changes and deletes
/// need a real id from calendar_list, and a delete must also name the event, so a wrong guess is refused.
public struct CalendarTools: ToolKit {
    public let name = "calendar"
    private let source: CalendarSource

    public init(source: CalendarSource) {
        self.source = source
    }

    public var instructions: String { "Read, add, change and delete calendar events." }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "add", description: "Add an event. start is local time \"YYYY-MM-DD HH:MM\", or \"YYYY-MM-DD\" for all day.",
                           schema: #"{"type":"object","properties":{"title":{"type":"string"},"start":{"type":"string"},"minutes":{"type":"integer"}},"required":["title","start"]}"#),
            ToolDefinition(name: "list", description: "List events with their ids from a day (\"YYYY-MM-DD\") for a number of days.",
                           schema: #"{"type":"object","properties":{"day":{"type":"string"},"days":{"type":"integer"}},"required":["day"]}"#),
            ToolDefinition(name: "change", description: "Move, retime or rename one event by its id from calendar_list. start is \"YYYY-MM-DD HH:MM\" or \"YYYY-MM-DD\" for all day; the length stays the same unless minutes is given.",
                           schema: #"{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"},"start":{"type":"string"},"minutes":{"type":"integer"}},"required":["id"]}"#),
            ToolDefinition(name: "delete", description: "Delete one event by its id from calendar_list; title is its name, as a check.",
                           schema: #"{"type":"object","properties":{"id":{"type":"string"},"title":{"type":"string"}},"required":["id","title"]}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        return try await MainActor.run {
            switch name {
            case "add":
                let event = try Self.event(input, now: .now)
                let item = try source.add(title: event.title, start: event.start, end: event.end, allDay: event.allDay)
                return CalendarCommand.confirmation(item)
            case "list":
                guard let day = Self.parse(input["day"] as? String ?? "")?.date else {
                    throw ChatError("day must look like 2026-10-14.")
                }
                let days = min(max((input["days"] as? NSNumber)?.intValue ?? 1, 1), 14)
                let end = day.addingTimeInterval(TimeInterval(days) * 86_400)
                guard let items = source.events(from: day, to: end) else { throw ChatError("Calendar access is off.") }
                return CalendarCommand.context(items, start: day, end: end, ids: true)
            case "change":
                let item = try Self.existing(input, in: source)
                let changed = try Self.changed(item, input, now: .now)
                return CalendarCommand.confirmation(try source.change(id: item.id, title: changed.title, start: changed.start,
                                                                      end: changed.end, allDay: changed.allDay), verb: "Changed to")
            case "delete":
                let item = try Self.existing(input, in: source)
                let named = (input["title"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                let title = item.title.lowercased()
                guard !named.isEmpty, title.contains(named) || named.contains(title) else {
                    throw ChatError("That id is \"\(item.title)\", not \"\(named)\". Nothing was deleted.")
                }
                try source.delete(id: item.id)
                return CalendarCommand.confirmation(item, verb: "Deleted")
            default:
                throw ChatError("No tool named \(name).")
            }
        }
    }

    @MainActor
    static func existing(_ input: [String: Any], in source: CalendarSource) throws -> AgendaItem {
        let id = (input["id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, let item = source.event(id: id) else {
            throw ChatError("No event has id \"\(id)\". Call calendar_list for real ids.")
        }
        return item
    }

    /// The event with the new title, start or length from `input`; anything not given stays as it was.
    static func changed(_ item: AgendaItem, _ input: [String: Any], now: Date) throws -> CalendarCommand.NewEvent {
        let title = (input["title"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? item.title
        let length = Int(item.end.timeIntervalSince(item.start) / 60)
        guard let text = input["start"] as? String, !text.isEmpty else {
            let minutes = (input["minutes"] as? NSNumber)?.intValue ?? length
            let end = item.allDay ? item.end : item.start.addingTimeInterval(TimeInterval(min(max(minutes, 5), 24 * 60) * 60))
            return .init(title: title, start: item.start, end: end, allDay: item.allDay)
        }
        var moved = input
        moved["title"] = title
        if moved["minutes"] == nil, !item.allDay { moved["minutes"] = length }
        return try event(moved, now: now)
    }

    static func event(_ input: [String: Any], now: Date) throws -> CalendarCommand.NewEvent {
        let title = (input["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw ChatError("title is missing.") }
        guard let start = parse(input["start"] as? String ?? "") else {
            throw ChatError("start must look like \"2026-10-14 15:00\" or \"2026-10-14\".")
        }
        guard start.date > now.addingTimeInterval(-86_400), start.date < now.addingTimeInterval(2 * 365 * 86_400) else {
            throw ChatError("That date is in the past or too far ahead; check the year.")
        }
        if start.allDay {
            return .init(title: title, start: start.date, end: start.date.addingTimeInterval(86_400), allDay: true)
        }
        let minutes = min(max((input["minutes"] as? NSNumber)?.intValue ?? 60, 5), 24 * 60)
        return .init(title: title, start: start.date, end: start.date.addingTimeInterval(TimeInterval(minutes * 60)), allDay: false)
    }

    /// "YYYY-MM-DD HH:MM" (also with a "T"), or "YYYY-MM-DD" for all day, in local time.
    static func parse(_ text: String) -> (date: Date, allDay: Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
        for (format, allDay) in [("yyyy-MM-dd HH:mm", false), ("yyyy-MM-dd HH:mm:ss", false), ("yyyy-MM-dd", true)] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return (date, allDay) }
        }
        return nil
    }
}
