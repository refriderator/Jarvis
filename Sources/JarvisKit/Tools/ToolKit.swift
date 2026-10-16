import Foundation

/// One tool a model can call: a name, what it does, and its input as a JSON Schema.
public struct ToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// JSON Schema text for the input object.
    public let schema: String

    public init(name: String, description: String, schema: String) {
        self.name = name
        self.description = description
        self.schema = schema
    }

    public var schemaObject: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(schema.utf8))) as? [String: Any] ?? ["type": "object"]
    }
}

/// A set of tools (e.g. Notion). Claude API calls them directly; Claude Code reaches them through
/// Jarvis's own MCP server (`Jarvis <mcpFlag>`).
public protocol ToolKit: Sendable {
    /// Short name, also the MCP server name ("notion").
    var name: String { get }
    /// Command-line flag that starts Jarvis as this tool kit's MCP server; nil when the tools only work inside the app.
    var mcpFlag: String? { get }
    /// Added to the system prompt when the tools are offered.
    var instructions: String { get }
    var definitions: [ToolDefinition] { get }
    /// Secrets the MCP server needs, handed over in its environment (never the command line, a file or logs).
    var environment: [String: String] { get }
    /// Runs a tool. `arguments` is the JSON input object; the result is text for the model.
    func call(_ name: String, arguments: Data) async throws -> String
}

extension ToolKit {
    public var mcpFlag: String? { nil }
    public var environment: [String: String] { [:] }
}
