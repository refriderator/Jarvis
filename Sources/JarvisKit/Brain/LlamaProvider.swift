import Foundation

/// A model that Jarvis downloaded and runs itself, with no Ollama or other install.
@MainActor
public struct LlamaProvider: ChatProvider {
    public let label: String
    public var canUseTools: Bool { true }
    private let engine: LlamaEngine
    private let modelPath: String

    public init(engine: LlamaEngine, model: LocalModel) {
        self.engine = engine
        self.modelPath = LocalModels.fileURL(model).path
        self.label = model.name
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        // "/no_think" switches Qwen3's long reasoning off, which would be slow to speak.
        let messages = [("system", system + " /no_think")] + history.map { ($0.role.rawValue, $0.text) }
        let result = try await engine.generate(modelPath: modelPath, messages: messages)
        return ChatReply(text: result.text, inputTokens: result.input, outputTokens: result.output)
    }
}
