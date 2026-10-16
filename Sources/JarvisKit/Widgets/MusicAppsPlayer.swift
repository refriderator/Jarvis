import AppKit

/// Now playing for Apple Music and Spotify: live updates from their broadcast
/// notifications, controls and the first lookup through AppleScript.
@MainActor
public final class MusicAppsPlayer: NowPlayingSource {
    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func observe(_ onChange: @escaping @MainActor (NowPlaying?) -> Void) {
        for player in MusicPlayer.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: player.changeNotification, object: nil, queue: .main
            ) { note in
                let playing = NowPlaying.from(notification: note.userInfo ?? [:], player: player)
                MainActor.assumeIsolated { onChange(playing) }
            }
            observers.append(observer)
        }
    }

    public func current() -> NowPlaying? {
        let found = running().compactMap { player in
            run(script(player, "if player state is stopped then return \"\"\n"
                + "set t to current track\n"
                + "return (name of t) & linefeed & (artist of t) & linefeed & (player state as text)"))
                .flatMap { NowPlaying.from(script: $0, player: player) }
        }
        return found.first { $0.isPlaying } ?? found.first
    }

    public func playPause(_ player: MusicPlayer?) {
        guard let target = player ?? running().first else { return }
        _ = run(script(target, "playpause"))
    }

    public func next(_ player: MusicPlayer?) {
        guard let target = player ?? running().first else { return }
        _ = run(script(target, "next track"))
    }

    public func previous(_ player: MusicPlayer?) {
        guard let target = player ?? running().first else { return }
        _ = run(script(target, "previous track"))
    }

    public func open(_ player: MusicPlayer?) {
        guard let target = player ?? running().first,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    public func play(_ query: String, in player: MusicPlayer) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue),
           !running().contains(player) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        switch player {
        case .music:
            // Searches the user's own library; Apple Music's catalog can't be searched from a script.
            let safe = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let source = script(.music, "set found to search playlist \"Library\" for \"\(safe)\"\n"
                + "if (count of found) is 0 then return \"\"\n"
                + "play item 1 of found\n"
                + "return (name of item 1 of found) & \" by \" & (artist of item 1 of found)")
            // Right after launch the app may not be ready to answer, so try once more.
            guard let found = run(source).flatMap({ $0.isEmpty ? nil : $0 }) ?? retry(source) else {
                return "I couldn't find \"\(query)\" in your Apple Music library."
            }
            return "Playing \(found)."
        case .spotify:
            // Spotify's scripting can play a track it already has a link for, but can't look one up by name.
            // Its search page is the nearest thing until Spotify is connected like Notion.
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            if let url = URL(string: "spotify:search:\(encoded)") { NSWorkspace.shared.open(url) }
            return "I opened Spotify's search for \"\(query)\". I can't start a song by name there yet."
        }
    }

    private func retry(_ source: String) -> String? {
        Thread.sleep(forTimeInterval: 1.5)
        return run(source).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Only talks to apps that are already open, so it never launches one.
    private func running() -> [MusicPlayer] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MusicPlayer.allCases.filter { ids.contains($0.rawValue) }
    }

    private func script(_ player: MusicPlayer, _ body: String) -> String {
        "tell application id \"\(player.rawValue)\"\n\(body)\nend tell"
    }

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}
