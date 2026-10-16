import Foundation

/// Any `/chat/completions` endpoint: Ollama on this Mac, OpenAI, or similar.
@MainActor
public struct OpenAICompatibleProvider: ChatProvider {
    public let baseURL: String
    public let model: String
    public let apiKey: String?
    public let label: String
    /// Asks the model to answer straight away, without a thinking pass first (Ollama's `reasoning_effort: "none"`).
    /// Thinking models like Qwen3 otherwise spend most of a minute thinking and can return no answer at all.
    public let skipThinking: Bool
    /// Ollama models (Qwen, Gemma...) can follow the JSON tool format when used as the local brain.
    public var canUseTools: Bool { true }

    public init(baseURL: String, model: String, apiKey: String?, label: String, skipThinking: Bool = false) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.label = label
        self.skipThinking = skipThinking
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: trimmed + "/chat/completions") else { throw ChatError("Bad base URL: \(baseURL)") }
        let messages = [["role": "system", "content": system]]
            + history.map { ["role": $0.role.rawValue, "content": $0.text] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        if skipThinking { body["reasoning_effort"] = "none" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ChatError("\(label): HTTP \(status)") }
        return try Self.parse(data)
    }

    nonisolated public static func parse(_ data: Data) throws -> ChatReply {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return ChatReply(text: decoded.choices.first?.message.content ?? "",
                         inputTokens: decoded.usage?.prompt_tokens ?? 0,
                         outputTokens: decoded.usage?.completion_tokens ?? 0)
    }
}
