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
        if starts.count == 1 { return starts.first.map { ($0.key, $0.value) } }
        // "whats" for WhatsApp: a longer start of one name, when nothing else starts the same way.
        let begins = all.filter { $0.key.lowercased().hasPrefix(wanted.lowercased()) }
        return wanted.count >= 4 && begins.count == 1 ? begins.first.map { ($0.key, $0.value) } : nil
    }
}

/// Runs `AppCommand`s: opens apps, docks their windows, controls and plays music. A nil reply means "not mine, ask a brain".
@MainActor
public final class AppLauncher {
    private let finder: AppFinder
    private let player: NowPlayingSource
    private let runningMusic: @MainActor () -> [MusicPlayer]
    /// Puts all of an app's windows in the notch's dock and says what happened, or throws why not. The notch is made
    /// after this, so the app fills it in; until then "dock X" is left to a brain.
    public var dockApp: ((String) throws -> String)?

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

    /// Opens an app by name (Notion falls back to its website when the app isn't installed). The name shown, or nil.
    @discardableResult
    public func open(_ spoken: String) -> String? {
        if let app = finder.find(spoken) {
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            return app.name
        }
        if spoken.lowercased() == "notion", let site = URL(string: "https://www.notion.so") {
            NSWorkspace.shared.open(site)
            return "Notion"
        }
        return nil
    }

    public func handle(_ text: String) -> String? {
        guard let command = AppCommand.parse(text) else { return nil }
        switch command {
        case .open(let name):
            if let opened = open(name) { return "Opening \(opened)." }
            // "open X" is plainly about an app, so say so rather than let a brain pretend it did something.
            // ("start" and "run" are too loose to claim.)
            return text.range(of: #"\b(open|launch)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                ? "I couldn't find an app called \(name)." : nil
        case .dock(let name):
            guard let dockApp else { return nil }
            do { return try dockApp(name) } catch { return error.localizedDescription }
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
