import Foundation

/// Claude through the API with the user's own key (billed per use by Anthropic).
/// Runs the tool loop itself when Notion tools are offered, and can look at a camera photo.
@MainActor
public struct ClaudeAPIProvider: ChatProvider {
    public let apiKey: String
    public let model: String
    public var label: String { "Claude" }
    public var supportsExtras: Bool { true }

    /// Models that take `fallbacks: "default"`, which reruns a declined request on another model.
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]
    /// Tool round trips allowed for one question.
    static let maxToolRounds = 8

    public init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        try await reply(system: system, history: history, extras: .none)
    }

    public func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply {
        var messages: [[String: Any]] = history.map { ["role": $0.role.rawValue, "content": $0.text] }
        if let image = extras.image, let last = history.last {
            messages[messages.count - 1]["content"] = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                ["type": "text", "text": last.text],
            ]
        }
        let tools = extras.tools
        let fullSystem = tools.map { system + "\n\n" + $0.instructions } ?? system
        var total = ChatReply(text: "")
        for _ in 0..<Self.maxToolRounds {
            let response = try await send(system: fullSystem, messages: messages, tools: tools)
            let step = try Self.parse(response.data, status: response.status)
            total.inputTokens += step.reply.inputTokens
            total.outputTokens += step.reply.outputTokens
            guard let tools, !step.toolCalls.isEmpty else {
                total.text = step.reply.text
                return total
            }
            // Echo Claude's whole turn back unchanged (thinking blocks included), then every result in one message.
            messages.append(["role": "assistant", "content": step.content])
            var results: [[String: Any]] = []
            for call in step.toolCalls {
                do {
                    let output = try await tools.call(call.name, arguments: call.input)
                    results.append(["type": "tool_result", "tool_use_id": call.id, "content": output])
                } catch {
                    results.append(["type": "tool_result", "tool_use_id": call.id, "content": error.localizedDescription,
                                    "is_error": true])
                }
            }
            messages.append(["role": "user", "content": results])
        }
        throw ChatError("Claude needed too many steps for that. Try asking for less at once.")
    }

    private func send(system: String, messages: [[String: Any]], tools: ToolKit?) async throws -> (data: Data, status: Int) {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            // Short spoken answers: low effort is plenty and keeps replies quick.
            "output_config": ["effort": "low"],
            "messages": messages,
        ]
        if let tools {
            body["tools"] = tools.definitions.map {
                ["name": "\(tools.name)_\($0.name)", "description": $0.description, "input_schema": $0.schemaObject]
            }
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if Self.fallbackModels.contains(model) {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    public struct ToolCall: Sendable {
        public let id: String
        /// Without the tool kit prefix ("search", not "notion_search").
        public let name: String
        public let input: Data
    }

    public struct Step: @unchecked Sendable {
        public var reply: ChatReply
        public var toolCalls: [ToolCall]
        /// The raw content blocks, to send back as the assistant turn.
        public var content: [[String: Any]]
    }

    nonisolated public static func parse(_ data: Data, status: Int) throws -> Step {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw ChatError(status == 401 ? "The Claude API key was rejected." : "Claude API: \(detail)")
        }
        guard let content = json["content"] as? [[String: Any]], let usage = json["usage"] as? [String: Any] else {
            throw ChatError("Claude API sent something unexpected.")
        }
        if json["stop_reason"] as? String == "refusal" {
            throw ChatError("Claude declined to answer that.")
        }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        let calls = json["stop_reason"] as? String == "tool_use" ? content.compactMap(toolCall) : []
        func count(_ key: String) -> Int { usage[key] as? Int ?? 0 }
        let input = count("input_tokens") + count("cache_creation_input_tokens") + count("cache_read_input_tokens")
        return Step(reply: ChatReply(text: text, inputTokens: input, outputTokens: count("output_tokens")),
                    toolCalls: calls, content: content)
    }

    nonisolated private static func toolCall(_ block: [String: Any]) -> ToolCall? {
        guard block["type"] as? String == "tool_use", let id = block["id"] as? String,
              let name = block["name"] as? String else { return nil }
        let input = (try? JSONSerialization.data(withJSONObject: block["input"] ?? [:])) ?? Data("{}".utf8)
        let bare = name.split(separator: "_", maxSplits: 1).last.map(String.init) ?? name
        return ToolCall(id: id, name: bare, input: input)
    }
}
