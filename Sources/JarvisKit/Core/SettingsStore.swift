import Foundation

/// Where `Settings` is kept between launches.
public protocol SettingsStore: Sendable {
    func load() -> Settings
    func save(_ settings: Settings)
}

/// `~/Library/Application Support/Jarvis/settings.json`.
public struct FileSettingsStore: SettingsStore {
    public let url: URL

    public init(url: URL = FileSettingsStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Jarvis/settings.json")
    }

    /// Missing or unreadable file means defaults; a bad file is never fatal.
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url), let settings = try? Settings.decode(data) else {
            return Settings()
        }
        return settings
    }

    public func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// For tests and previews.
public final class MemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: Settings

    public init(_ settings: Settings = Settings()) {
        self.settings = settings
    }

    public func load() -> Settings {
        lock.withLock { settings }
    }

    public func save(_ settings: Settings) {
        lock.withLock { self.settings = settings }
    }
}
