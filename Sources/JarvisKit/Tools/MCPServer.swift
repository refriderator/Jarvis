import Foundation

/// A minimal MCP server over stdin/stdout, so Claude Code can use Jarvis's tools
/// (`claude --mcp-config` points at `Jarvis --notion-mcp`). One JSON-RPC message per line.
public enum MCPServer {
    public static func run(_ tools: ToolKit) async {
        for await line in lines() {
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let method = message["method"] as? String else { continue }
            // Notifications have no id and get no reply.
            guard let id = message["id"] else { continue }
            let params = message["params"] as? [String: Any] ?? [:]
            let result = await respond(method, params: params, tools: tools)
            var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
            switch result {
            case .success(let value): reply["result"] = value
            case .failure(let error): reply["error"] = ["code": -32601, "message": error.message]
            }
            write(reply)
        }
    }

    public static func respond(_ method: String, params: [String: Any], tools: ToolKit) async -> Result<[String: Any], ChatError> {
        switch method {
        case "initialize":
            return .success(["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                             "capabilities": ["tools": [:] as [String: Any]],
                             "serverInfo": ["name": "jarvis-\(tools.name)", "version": "1.0"],
                             "instructions": tools.instructions])
        case "ping":
            return .success([:])
        case "tools/list":
            return .success(["tools": tools.definitions.map {
                ["name": $0.name, "description": $0.description, "inputSchema": $0.schemaObject]
            }])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = (try? JSONSerialization.data(withJSONObject: params["arguments"] ?? [:])) ?? Data("{}".utf8)
            do {
                let text = try await tools.call(name, arguments: arguments)
                return .success(["content": [["type": "text", "text": text]]])
            } catch {
                return .success(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            return .failure(ChatError("Unknown method \(method)"))
        }
    }

    private static func lines() -> AsyncStream<String> {
        AsyncStream { continuation in
            Thread.detachNewThread {
                while let line = readLine(strippingNewline: true) { continuation.yield(line) }
                continuation.finish()
            }
        }
    }

    private static func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
