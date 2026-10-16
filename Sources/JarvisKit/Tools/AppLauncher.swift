import AppKit

/// Finds installed apps by the name someone says, and opens them.
@MainActor
public protocol AppFinder {
    /// The app's display name and location, or nil when nothing installed fits (never a guess between two).
    func find(_ spoken: String) -> (name: String, url: URL)?
}

/// Looks in the usual Applications folders. Spoken short names ("word", "chrome") come from a small table;
/// otherwise the name must match an installed app exactly, or be the start of exactly one app's name.
@MainActor
public final class InstalledApps: AppFinder {
    private static let aliases = ["word": "Microsoft Word", "excel": "Microsoft Excel", "powerpoint": "Microsoft PowerPoint",
                                  "outlook": "Microsoft Outlook", "teams": "Microsoft Teams", "chrome": "Google Chrome",
                                  "vs code": "Visual Studio Code", "vscode": "Visual Studio Code", "code": "Visual Studio Code",
                                  "settings": "System Settings", "system preferences": "System Settings",
                                  "music": "Music", "apple music": "Music", "messages": "Messages", "imessage": "Messages"]
    private var cache: [String: URL]?

    public init() {}

    private func apps() -> [String: URL] {
        if let cache { return cache }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var found: [String: URL] = [:]
        for folder in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities", home + "/Applications"] {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for item in items where item.hasSuffix(".app") {
                found[String(item.dropLast(4))] = URL(fileURLWithPath: folder).appending(path: item)
            }
        }
        cache = found
        return found
    }

    public func find(_ spoken: String) -> (name: String, url: URL)? {
        let all = apps()
        let words = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return nil }
        let wanted = Self.aliases[words] ?? words
        if let exact = all.first(where: { $0.key.lowercased() == wanted.lowercased() }) { return (exact.key, exact.value) }
        let starts = all.filter { $0.key.lowercased().hasPrefix(wanted.lowercased() + " ") }
        return starts.count == 1 ? starts.first.map { ($0.key, $0.value) } : nil
    }
}

/// Runs `AppCommand`s: opens apps, controls and plays music. A nil reply means "not mine, ask a brain".
@MainActor
public final class AppLauncher {
    private let finder: AppFinder
    private let player: NowPlayingSource
    private let runningMusic: @MainActor () -> [MusicPlayer]

    public init(finder: AppFinder = InstalledApps(), player: NowPlayingSource,
                runningMusic: @escaping @MainActor () -> [MusicPlayer] = AppLauncher.runningMusicApps) {
        self.finder = finder
        self.player = player
        self.runningMusic = runningMusic
    }

    public static func runningMusicApps() -> [MusicPlayer] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MusicPlayer.allCases.filter { ids.contains($0.rawValue) }
    }

    public func handle(_ text: String) -> String? {
        guard let command = AppCommand.parse(text) else { return nil }
        switch command {
        case .open(let name):
            guard let app = finder.find(name) else { return nil }
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            return "Opening \(app.name)."
        case .control(let control):
            guard let target = runningMusic().first else { return nil }
            switch control {
            case .pause, .resume: player.playPause(target)
            case .next: player.next(target)
            case .previous: player.previous(target)
            }
            return control == .pause ? "Paused." : control == .resume ? "Playing." : control == .next ? "Next song." : "Previous song."
        case .play(let query, let app):
            let target = app.flatMap { $0 == "Spotify" ? MusicPlayer.spotify : MusicPlayer.music } ?? runningMusic().first
            guard let target, !query.isEmpty else { return nil }
            return player.play(query, in: target)
        }
    }
}
