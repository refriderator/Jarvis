import Foundation

/// One unfinished item with a due date, from any shared Notion database with a date column.
public struct DueItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let due: Date
    public let hasTime: Bool
    /// The database it came from, e.g. "Assignments".
    public let source: String

    public init(id: String, title: String, due: Date, hasTime: Bool, source: String) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.source = source
    }

    /// Its time has passed today, so the notch greys it out. Items with no time stay normal all day.
    public func isPast(_ now: Date) -> Bool { hasTime && due <= now }

    /// The time it's due today, or "All day".
    public var timeText: String {
        guard hasTime else { return "All day" }
        let minutes = Calendar.current.component(.minute, from: due)
        return due.formatted(minutes == 0 ? .dateTime.hour() : .dateTime.hour().minute())
    }

    /// "Thursday", "tomorrow at 6:45 AM", "Nov 30".
    public func whenText(now: Date = .now) -> String { NotionAPI.friendly(due, hasTime: hasTime, now: now) }
}

extension NotionAPI {
    /// Everything not yet done with a date from today on, across every shared database that has a date
    /// column (or only `databaseID`), soonest first. Nil when no database is shared with the integration.
    public func dueItems(databaseID: String? = nil, days: Int, now: Date = .now) async throws -> [DueItem]? {
        let databases: [[String: Any]]
        if let databaseID {
            databases = [try await send("GET", "databases/\(databaseID)")]
        } else {
            let found = try await send("POST", "search", body: ["filter": ["property": "object", "value": "database"],
                                                                "page_size": 20])
            databases = found["results"] as? [[String: Any]] ?? []
        }
        guard !databases.isEmpty else { return nil }
        let today = Calendar.current.startOfDay(for: now)
        let end = today.addingTimeInterval(TimeInterval(days) * 86_400)
        var items: [DueItem] = []
        for database in databases {
            let properties = database["properties"] as? [String: [String: Any]] ?? [:]
            guard let id = database["id"] as? String, let dateColumn = Self.dateColumn(properties) else { continue }
            let rows = try await send("POST", "databases/\(id)/query", body: [
                "filter": ["and": [["property": dateColumn, "date": ["on_or_after": Self.day(today)]],
                                   ["property": dateColumn, "date": ["before": Self.day(end)]]]],
                "sorts": [["property": dateColumn, "direction": "ascending"]],
                "page_size": 50,
            ])
            let source = Self.title(of: database)
            for row in rows["results"] as? [[String: Any]] ?? [] {
                let values = row["properties"] as? [String: [String: Any]] ?? [:]
                guard !Self.isDone(values), let raw = (values[dateColumn]?["date"] as? [String: Any])?["start"] as? String,
                      let due = Self.date(raw) else { continue }
                items.append(DueItem(id: row["id"] as? String ?? UUID().uuidString, title: Self.title(of: row),
                                     due: due.date, hasTime: due.hasTime, source: source))
            }
        }
        return items.sorted { $0.due < $1.due }
    }

    /// `dueItems` as text for a model, exams and coursework apart, each soonest first:
    /// "Exams:\n- PHY224 Midterm — due Oct 19 at 10 AM (Exams, id …)\nCoursework:\n- MAT244 Online PS — …".
    /// Telling exams from coursework, and reading a mixed list in order, is what the small local model got wrong
    /// most ("all my exams" 0/10), so code does it, as the calculator does sums.
    public func upcoming(databaseID: String?, days: Int, now: Date = .now) async throws -> String {
        guard let items = try await dueItems(databaseID: databaseID, days: days, now: now) else {
            return "No databases are shared with the Jarvis integration yet. Share them in Notion: ••• › Connections."
        }
        return Self.grouped(items, days: days, now: now)
    }

    public static func grouped(_ items: [DueItem], days: Int, now: Date) -> String {
        guard !items.isEmpty else { return "Nothing due in the next \(days) days." }
        func lines(_ group: [DueItem]) -> String {
            group.map { "- \($0.title) — due \($0.whenText(now: now)) (\($0.source), id \($0.id))" }.joined(separator: "\n")
        }
        let exams = items.filter { isExam($0.title) }, work = items.filter { !isExam($0.title) }
        return [exams.isEmpty ? nil : "Exams:\n" + lines(exams), work.isEmpty ? nil : "Coursework:\n" + lines(work)]
            .compactMap { $0 }.joined(separator: "\n")
    }

    /// An exam is anything titled with one of these words: "MIDTERM!!!!! PHY224", "MAT244 Quiz", "Test 1 – Psych".
    public static func isExam(_ title: String) -> Bool {
        title.range(of: #"\b(midterms?|exams?|tests?|quiz(zes)?|finals?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: Dates and done-ness

    /// The column holding due dates: one named like "Due", else the first date column.
    public static func dateColumn(_ properties: [String: [String: Any]]) -> String? {
        let dates = properties.filter { $0.value["type"] as? String == "date" }.map(\.key).sorted()
        return dates.first { $0.range(of: #"due|deadline|date"#, options: [.regularExpression, .caseInsensitive]) != nil }
            ?? dates.first
    }

    /// A ticked "Done" checkbox, or a status/select like Done, Complete, Submitted.
    public static func isDone(_ properties: [String: [String: Any]]) -> Bool {
        properties.contains { name, value in
            switch value["type"] as? String {
            case "checkbox":
                return value["checkbox"] as? Bool == true
                    && name.range(of: #"done|complete|submitted|finished"#, options: [.regularExpression, .caseInsensitive]) != nil
            case let type? where type == "status" || type == "select":
                let state = ((value[type] as? [String: Any])?["name"] as? String ?? "").lowercased()
                return ["done", "complete", "completed", "submitted", "finished", "handed in"].contains(state)
            default:
                return false
            }
        }
    }

    /// Notion's "2026-10-16" or "2026-10-16T06:45:00.000-04:00".
    public static func date(_ text: String) -> (date: Date, hasTime: Bool)? {
        if text.count == 10 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text).map { ($0, false) }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return (date, true) }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text).map { ($0, true) }
    }

    public static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "today at 3 PM", "tomorrow", "Thursday at 6:45 AM", "Oct 30": how you'd say it.
    public static func friendly(_ date: Date, hasTime: Bool, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let dayText = switch days {
        case 0: "today"
        case 1: "tomorrow"
        case 2..<7: date.formatted(.dateTime.weekday(.wide))
        default: date.formatted(.dateTime.month(.abbreviated).day())
        }
        guard hasTime else { return dayText }
        let minutes = calendar.component(.minute, from: date)
        return "\(dayText) at \(date.formatted(minutes == 0 ? .dateTime.hour() : .dateTime.hour().minute()))"
    }
}
