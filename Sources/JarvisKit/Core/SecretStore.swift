import Foundation

/// The secrets Jarvis keeps. They only ever live in a `SecretStore` (the Keychain
/// in the app), never in settings files or logs.
public enum SecretKey: String, Sendable, CaseIterable {
    case claudeAPIKey = "claude-api-key"
    case compatibleAPIKey = "openai-compatible-api-key"
    case notionToken = "notion-token"
}

public protocol SecretStore: Sendable {
    func get(_ key: SecretKey) -> String?
    /// nil or empty deletes the secret.
    func set(_ key: SecretKey, _ value: String?)
}

/// For tests and previews.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String] = [:]

    public init() {}

    public func get(_ key: SecretKey) -> String? {
        lock.withLock { values[key] }
    }

    public func set(_ key: SecretKey, _ value: String?) {
        lock.withLock { values[key] = (value?.isEmpty ?? true) ? nil : value }
    }
}
