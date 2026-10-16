import Foundation

public struct ChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable {
        case user, assistant
    }

    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

public struct ChatReply: Equatable, Sendable {
    public var text: String
    /// Everything the model read, cached or not; 0 when the provider doesn't say (on-device).
    public var inputTokens: Int
    public var outputTokens: Int

    public init(text: String, inputTokens: Int = 0, outputTokens: Int = 0) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

public struct ChatError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// What a question needs beyond text: a camera photo, or tools (Notion).
public struct ChatExtras: Sendable {
    /// A JPEG to look at alongside the last message.
    public var image: Data?
    public var tools: ToolKit?

    public init(image: Data? = nil, tools: ToolKit? = nil) {
        self.image = image
        self.tools = tools
    }

    public static let none = ChatExtras()
    public var isEmpty: Bool { image == nil && tools == nil }
}

/// Something that answers: a cloud model, Claude Code, or a model on this Mac.
@MainActor
public protocol ChatProvider {
    /// Shown on the caption, e.g. "Claude" or "On-device".
    var label: String { get }
    /// Whether `reply(system:history:extras:)` uses photos and tools.
    var supportsExtras: Bool { get }
    /// A local model good enough to call tools by replying with JSON (see `LocalToolLoop`).
    var canUseTools: Bool { get }
    /// `history` ends with the user's new message.
    func reply(system: String, history: [ChatMessage]) async throws -> ChatReply
    func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply
}

extension ChatProvider {
    public var supportsExtras: Bool { false }
    public var canUseTools: Bool { false }

    public func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply {
        try await reply(system: system, history: history)
    }
}

extension [ChatMessage] {
    /// One prompt for providers that take a single string: earlier turns, then the new question.
    var flattened: String {
        guard count > 1, let last else { return last?.text ?? "" }
        let earlier = dropLast().map { "\($0.role == .user ? "User" : "Jarvis"): \($0.text)" }
        return "Conversation so far:\n\(earlier.joined(separator: "\n"))\n\nUser: \(last.text)"
    }
}
