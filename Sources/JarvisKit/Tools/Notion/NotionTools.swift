import Foundation

/// Notion as tools the cloud brain can call.
public struct NotionTools: ToolKit {
    public let name = "notion"
    public static let flag = "--notion-mcp"
    public var mcpFlag: String? { Self.flag }
    /// Where `Jarvis --notion-mcp` finds the token.
    public static let tokenVariable = "JARVIS_NOTION_TOKEN"
    private let api: NotionAPI
    private let token: String

    public init(token: String) {
        self.token = token
        api = NotionAPI(token: token)
    }

    public var environment: [String: String] { [Self.tokenVariable: token] }

    public var instructions: String {
        """
        You are connected to the user's Notion and can read and change it with the notion tools: do it, \
        don't say you can't access Notion or ask the user to check it themselves. For anything due, assignments, \
        homework or deadlines, call due first. To tick something off a list, call tick. Otherwise search to find the page or database, read a page before \
        changing it, and only change what was asked. If a tool returns an error, fix the arguments and try again. \
        When reporting what's due, say each item and when, like "MAT244 Online PS is due Thursday". \
        Afterwards say in one or two sentences what you found or did.
        """
    }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "due", description: "What's due: unfinished items with a date from today on, from every shared database with a date column (or one database_id), as Exams then Coursework, each soonest first.",
                           schema: #"{"type":"object","properties":{"days":{"type":"integer","description":"How many days ahead, default 14"},"database_id":{"type":"string"}}}"#),
            ToolDefinition(name: "search", description: "Find Notion pages and databases by title. Use an empty query to list everything shared.",
                           schema: #"{"type":"object","properties":{"query":{"type":"string"}}}"#),
            ToolDefinition(name: "read_page", description: "Read a page's title and content. To-dos include their block id.",
                           schema: #"{"type":"object","properties":{"page_id":{"type":"string"}},"required":["page_id"]}"#),
            ToolDefinition(name: "append_to_page", description: "Add lines to the end of a page, as to-dos or as paragraphs.",
                           schema: #"{"type":"object","properties":{"page_id":{"type":"string"},"lines":{"type":"array","items":{"type":"string"}},"as_todos":{"type":"boolean"}},"required":["page_id","lines"]}"#),
            ToolDefinition(name: "tick", description: "Tick (or untick) a to-do on a list by what it says, e.g. list \"groceries\", item \"milk\". Finds the list, finds the to-do and ticks it in one call.",
                           schema: #"{"type":"object","properties":{"list":{"type":"string"},"item":{"type":"string"},"checked":{"type":"boolean"}},"required":["list","item"]}"#),
            ToolDefinition(name: "set_todo", description: "Tick or untick a to-do by its block id.",
                           schema: #"{"type":"object","properties":{"block_id":{"type":"string"},"checked":{"type":"boolean"}},"required":["block_id","checked"]}"#),
            ToolDefinition(name: "create_page", description: "Create a page under a page, or a new row in a database (parent_id is the page or database id).",
                           schema: #"{"type":"object","properties":{"parent_id":{"type":"string"},"title":{"type":"string"},"text":{"type":"string"}},"required":["parent_id","title"]}"#),
            ToolDefinition(name: "query_database", description: "List a database's rows with their main properties.",
                           schema: #"{"type":"object","properties":{"database_id":{"type":"string"}},"required":["database_id"]}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        func text(_ key: String) throws -> String {
            guard let value = input[key] as? String, !value.isEmpty else { throw ChatError("Missing \(key).") }
            return value
        }
        switch name {
        case "due":
            let days = min(max((input["days"] as? NSNumber)?.intValue ?? 14, 1), 90)
            let database = (input["database_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return try await api.upcoming(databaseID: database, days: days)
        case "search": return try await api.search(input["query"] as? String ?? "")
        case "read_page": return try await api.readPage(try text("page_id"))
        case "append_to_page":
            return try await api.append(to: try text("page_id"), lines: input["lines"] as? [String] ?? [],
                                        asTodos: input["as_todos"] as? Bool ?? false)
        case "tick":
            return try await api.tick(list: try text("list"), item: try text("item"), checked: input["checked"] as? Bool ?? true)
        case "set_todo": return try await api.setTodo(try text("block_id"), checked: input["checked"] as? Bool ?? true)
        case "create_page":
            return try await api.createPage(parentID: try text("parent_id"), title: try text("title"),
                                            text: input["text"] as? String)
        case "query_database": return try await api.queryDatabase(try text("database_id"))
        default: throw ChatError("No tool named \(name).")
        }
    }
}
