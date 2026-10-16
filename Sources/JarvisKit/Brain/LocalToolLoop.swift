import Foundation

/// Lets a local model (Qwen etc.) use tools: it replies with one line of JSON to call a tool,
/// Jarvis runs it and sends the result back, until the model answers in plain text.
/// The tools check every value themselves, so a wrong guess is refused rather than acted on.
@MainActor
public enum LocalToolLoop {
    public static let maxRounds = 6

    /// What the model is told: how to call tools, an optional hint, then every tool with its arguments.
    /// Public so fine-tuning scripts can build the exact prompt the app sends.
    public static func systemPrompt(kits: [ToolKit], hint: String? = nil) -> String {
        Persona.localTools + (hint.map { "\n\n" + $0 } ?? "") + "\n\nTools:\n" + kits.flatMap { kit in
            kit.definitions.map { "- \(kit.name)_\($0.name): \($0.description) Arguments: \($0.schema)" }
        }.joined(separator: "\n")
    }

    public static func run(_ model: ChatProvider, history: [ChatMessage], kits: [ToolKit],
                           hint: String? = nil) async throws -> ChatReply {
        let system = systemPrompt(kits: kits, hint: hint)
        var messages = history
        var total = ChatReply(text: "")
        var lastResult: String?
        for _ in 0..<maxRounds {
            let reply = try await model.reply(system: system, history: messages)
            total.inputTokens += reply.inputTokens
            total.outputTokens += reply.outputTokens
            guard let call = parseCall(reply.text) else {
                // Broken JSON is a failed tool call, never an answer to show or read aloud.
                if looksLikeJSON(reply.text) {
                    messages += [ChatMessage(.assistant, reply.text),
                                 ChatMessage(.user, "That wasn't valid JSON. Send the tool call again, exactly one JSON object.")]
                    continue
                }
                total.text = reply.text
                return total
            }
            guard let kit = kits.first(where: { call.tool.hasPrefix($0.name + "_") }) else {
                messages += [ChatMessage(.assistant, reply.text),
                             ChatMessage(.user, "There is no tool called \(call.tool). Use one from the list, or answer.")]
                continue
            }
            let name = String(call.tool.dropFirst(kit.name.count + 1))
            let result: String
            do {
                result = try await kit.call(name, arguments: call.arguments)
                lastResult = result
            } catch {
                result = "Error: \(error.localizedDescription)"
            }
            messages += [ChatMessage(.assistant, reply.text), ChatMessage(.user, "Result of \(call.tool):\n\(result)")]
        }
        // Out of rounds: if something was done, say so rather than handing it to the cloud to do twice.
        guard let lastResult else { throw ChatError("The local brain couldn't finish that.") }
        total.text = lastResult
        return total
    }

    public struct Call: Equatable {
        public var tool: String
        public var arguments: Data
    }

    /// `{"tool": ..., "arguments": {...}}`, also inside ``` fences or Qwen's own `<tool_call>` tags
    /// and with "name" instead of "tool". Plain text is not a call.
    nonisolated public static func parseCall(_ text: String) -> Call? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for wrapper in ["```json", "```", "<tool_call>", "</tool_call>"] {
            trimmed = trimmed.replacingOccurrences(of: wrapper, with: "")
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let object = firstObject(in: trimmed),
              let tool = (object["tool"] ?? object["name"]) as? String else { return nil }
        let arguments = (try? JSONSerialization.data(withJSONObject: object["arguments"] ?? [:])) ?? Data("{}".utf8)
        return Call(tool: tool, arguments: arguments)
    }

    nonisolated static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("```") || trimmed.hasPrefix("<tool_call>")
    }

    /// The first balanced `{...}`, so a stray extra brace or trailing words after it don't spoil the call.
    nonisolated static func firstObject(in text: String) -> [String: Any]? {
        var depth = 0, inString = false, escaped = false
        for (index, character) in zip(text.indices, text) {
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return (try? JSONSerialization.jsonObject(with: Data(text[...index].utf8))) as? [String: Any]
                }
            default: break
            }
        }
        return nil
    }
}
