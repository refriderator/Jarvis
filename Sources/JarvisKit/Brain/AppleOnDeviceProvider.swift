import FoundationModels

/// Apple's on-device model (Apple Intelligence): free, private, works offline. Needs macOS 26; on older systems
/// it's simply never available.
@MainActor
public struct AppleOnDeviceProvider: ChatProvider {
    public var label: String { "On-device" }

    public init() {}

    public static var isAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        guard #available(macOS 26, *) else { throw ChatError("Apple's on-device model needs macOS 26.") }
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(to: history.flattened)
        return ChatReply(text: response.content)
    }
}
