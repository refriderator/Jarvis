import Foundation

/// The parts of Notion's REST API Jarvis uses, with the user's integration token.
/// Pages must be shared with the integration in Notion (••• › Connections) to be visible.
public struct NotionAPI: Sendable {
    public static let version = "2022-06-28"
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func search(_ query: String) async throws -> String {
        let json = try await send("POST", "search", body: ["query": query, "page_size": query.isEmpty ? 25 : 10])
        let results = json["results"] as? [[String: Any]] ?? []
        guard !results.isEmpty else {
            return "Nothing found. Pages only show up once they're shared with the Jarvis integration in Notion."
        }
        return results.map { item in
            let kind = item["object"] as? String ?? "page"
            return "- \(Self.title(of: item)) (\(kind), id \(item["id"] as? String ?? "?"))"
        }.joined(separator: "\n")
    }

    /// The page's title and its blocks as plain text; to-dos carry their block id so they can be ticked.
    public func readPage(_ id: String) async throws -> String {
        let page = try await send("GET", "pages/\(id)")
        let blocks = try await send("GET", "blocks/\(id)/children?page_size=100")
        let lines = (blocks["results"] as? [[String: Any]] ?? []).compactMap(Self.line)
        return "# \(Self.title(of: page))\n" + (lines.isEmpty ? "(empty page)" : lines.joined(separator: "\n"))
    }

    public func append(to pageID: String, lines: [String], asTodos: Bool) async throws -> String {
        let type = asTodos ? "to_do" : "paragraph"
        let children: [[String: Any]] = lines.map { line in
            var content: [String: Any] = ["rich_text": [["type": "text", "text": ["content": line]]]]
            if asTodos { content["checked"] = false }
            return ["object": "block", "type": type, type: content]
        }
        _ = try await send("PATCH", "blocks/\(pageID)/children", body: ["children": children])
        return "Added \(lines.count) \(asTodos ? "to-do" : "line")\(lines.count == 1 ? "" : "s")."
    }

    /// Ticks (or unticks) a to-do by what it says, on a list found by name: search, read and tick in one go,
    /// since the local model often stopped after reading the list. "Ticked milk off Errands."
    public func tick(list: String, item: String, checked: Bool) async throws -> String {
        let found = try await send("POST", "search", body: ["query": list, "page_size": 10,
                                                            "filter": ["property": "object", "value": "page"]])
        guard let page = (found["results"] as? [[String: Any]])?.first, let pageID = page["id"] as? String else {
            return "No page called \"\(list)\" is shared with the Jarvis integration."
        }
        let title = Self.title(of: page)
        let blocks = try await send("GET", "blocks/\(pageID)/children?page_size=100")
        let todos = (blocks["results"] as? [[String: Any]] ?? []).compactMap { block -> (id: String, text: String)? in
            guard block["type"] as? String == "to_do", let id = block["id"] as? String,
                  let content = block["to_do"] as? [String: Any] else { return nil }
            return (id, Self.plain(content["rich_text"]))
        }
        guard let todo = todos.first(where: { $0.text.localizedCaseInsensitiveContains(item) }) else {
            let names = todos.map(\.text).joined(separator: ", ")
            return "\(title) has no to-do like \"\(item)\". " + (names.isEmpty ? "It has no to-dos." : "Its to-dos: \(names).")
        }
        _ = try await send("PATCH", "blocks/\(todo.id)", body: ["to_do": ["checked": checked]])
        return "\(checked ? "Ticked" : "Unticked") \(todo.text) \(checked ? "off" : "on") \(title)."
    }

    public func setTodo(_ blockID: String, checked: Bool) async throws -> String {
        _ = try await send("PATCH", "blocks/\(blockID)", body: ["to_do": ["checked": checked]])
        return checked ? "Ticked." : "Unticked."
    }

    /// A new page under a page, or a new row in a database (titled with the database's title column).
    public func createPage(parentID: String, title: String, text: String?) async throws -> String {
        let titleValue: [[String: Any]] = [["type": "text", "text": ["content": title]]]
        var body: [String: Any]
        if let database = try? await send("GET", "databases/\(parentID)") {
            let properties = database["properties"] as? [String: [String: Any]] ?? [:]
            let titleColumn = properties.first { $0.value["type"] as? String == "title" }?.key ?? "Name"
            body = ["parent": ["database_id": parentID], "properties": [titleColumn: ["title": titleValue]]]
        } else {
            body = ["parent": ["page_id": parentID], "properties": ["title": ["title": titleValue]]]
        }
        if let text, !text.isEmpty {
            body["children"] = text.split(separator: "\n").map { line in
                ["object": "block", "type": "paragraph",
                 "paragraph": ["rich_text": [["type": "text", "text": ["content": String(line)]]]]]
            }
        }
        let page = try await send("POST", "pages", body: body)
        return "Created \"\(title)\" (id \(page["id"] as? String ?? "?"))."
    }

    public func queryDatabase(_ id: String) async throws -> String {
        let json = try await send("POST", "databases/\(id)/query", body: ["page_size": 25])
        let rows = json["results"] as? [[String: Any]] ?? []
        guard !rows.isEmpty else { return "The database is empty." }
        return rows.map { row in
            let properties = row["properties"] as? [String: [String: Any]] ?? [:]
            let details = properties.compactMap { name, value in Self.propertyText(value).map { "\(name): \($0)" } }
            return "- \(Self.title(of: row)) (id \(row["id"] as? String ?? "?"))"
                + (details.isEmpty ? "" : " — " + details.sorted().joined(separator: ", "))
        }.joined(separator: "\n")
    }

    // MARK: HTTP

    func send(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(Self.version, forHTTPHeaderField: "notion-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if status == 401 { throw ChatError("Notion rejected the token. Check it in Settings › Connections.") }
            throw ChatError("Notion: \(json["message"] as? String ?? "HTTP \(status)")")
        }
        return json
    }

    // MARK: Plain text

    static func plain(_ richText: Any?) -> String {
        (richText as? [[String: Any]] ?? []).compactMap { $0["plain_text"] as? String }.joined()
    }

    static func title(of object: [String: Any]) -> String {
        if let title = object["title"] { return plain(title).isEmpty ? "Untitled" : plain(title) }
        let properties = object["properties"] as? [String: [String: Any]] ?? [:]
        let text = properties.values.first { $0["type"] as? String == "title" }.map { plain($0["title"]) } ?? ""
        return text.isEmpty ? "Untitled" : text
    }

    public static func line(_ block: [String: Any]) -> String? {
        guard let type = block["type"] as? String, let content = block[type] as? [String: Any] else { return nil }
        let text = plain(content["rich_text"])
        switch type {
        case "heading_1": return "# \(text)"
        case "heading_2": return "## \(text)"
        case "heading_3": return "### \(text)"
        case "bulleted_list_item", "toggle": return "- \(text)"
        case "numbered_list_item": return "1. \(text)"
        case "to_do":
            let box = content["checked"] as? Bool == true ? "[x]" : "[ ]"
            return "\(box) \(text) (block \(block["id"] as? String ?? "?"))"
        case "quote", "callout": return "> \(text)"
        case "child_page": return "Page: \(content["title"] as? String ?? "") (id \(block["id"] as? String ?? "?"))"
        case "child_database": return "Database: \(content["title"] as? String ?? "") (id \(block["id"] as? String ?? "?"))"
        default: return text.isEmpty ? nil : text
        }
    }

    static func propertyText(_ value: [String: Any]) -> String? {
        guard let type = value["type"] as? String else { return nil }
        switch type {
        case "rich_text": return plain(value["rich_text"]).nilIfEmpty
        case "select", "status": return (value[type] as? [String: Any])?["name"] as? String
        case "multi_select": return (value[type] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: ", ").nilIfEmpty
        case "date":
            guard let raw = (value["date"] as? [String: Any])?["start"] as? String, let parsed = date(raw) else { return nil }
            return friendly(parsed.date, hasTime: parsed.hasTime, now: .now)
        case "checkbox": return (value["checkbox"] as? Bool).map { $0 ? "yes" : "no" }
        case "number": return (value["number"] as? NSNumber)?.stringValue
        default: return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
