import Foundation

/// Token counts for the last reply, this session (since launch) and today. Tokens only, never money.
public struct TokenMeter: Equatable, Sendable {
    public private(set) var lastReply = 0
    public private(set) var session = 0
    public private(set) var today = 0
    /// Start of the day `today` counts.
    public private(set) var day: Date

    public init(today: Int = 0, day: Date = Calendar.current.startOfDay(for: .now)) {
        self.today = today
        self.day = day
    }

    public mutating func add(_ tokens: Int, now: Date = .now) {
        rollOver(now: now)
        lastReply = tokens
        session += tokens
        today += tokens
    }

    /// A new day starts `today` again from zero.
    public mutating func rollOver(now: Date = .now) {
        let start = Calendar.current.startOfDay(for: now)
        if start != day {
            day = start
            today = 0
        }
    }

    public mutating func reset() {
        lastReply = 0
        session = 0
        today = 0
    }
}

/// Keeps today's count across relaunches.
public protocol UsageStore: Sendable {
    func load() -> TokenMeter
    func save(_ meter: TokenMeter)
}

/// `~/Library/Application Support/Jarvis/usage.json`.
public struct FileUsageStore: UsageStore {
    private struct Saved: Codable {
        let today: Int
        let day: Date
    }

    public let url: URL

    public init(url: URL = URL.applicationSupportDirectory.appending(path: "Jarvis/usage.json")) {
        self.url = url
    }

    public func load() -> TokenMeter {
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return TokenMeter()
        }
        var meter = TokenMeter(today: saved.today, day: saved.day)
        meter.rollOver()
        return meter
    }

    public func save(_ meter: TokenMeter) {
        guard let data = try? JSONEncoder().encode(Saved(today: meter.today, day: meter.day)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// For tests and previews.
public struct MemoryUsageStore: UsageStore {
    public init() {}
    public func load() -> TokenMeter { TokenMeter() }
    public func save(_ meter: TokenMeter) {}
}
