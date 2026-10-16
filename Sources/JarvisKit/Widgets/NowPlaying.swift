import Foundation

/// A music app Jarvis can show and control.
public enum MusicPlayer: String, Sendable, CaseIterable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    /// Broadcast by the app on every track or play-state change; needs no permission to hear.
    public var changeNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var isPlaying: Bool
    public var player: MusicPlayer

    public init(title: String, artist: String, isPlaying: Bool, player: MusicPlayer) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.player = player
    }

    /// From a change notification's userInfo. nil when the player stopped.
    public static func from(notification info: [AnyHashable: Any], player: MusicPlayer) -> NowPlaying? {
        let state = (info["Player State"] as? String ?? "").lowercased()
        guard state != "stopped", let title = info["Name"] as? String, !title.isEmpty else { return nil }
        return NowPlaying(title: title, artist: info["Artist"] as? String ?? "",
                          isPlaying: state == "playing", player: player)
    }

    /// From `NowPlayingScript` output: "title\nartist\nstate", or "" when stopped.
    public static func from(script output: String, player: MusicPlayer) -> NowPlaying? {
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 3, !lines[0].isEmpty else { return nil }
        return NowPlaying(title: lines[0], artist: lines[1],
                          isPlaying: lines[2].lowercased() == "playing", player: player)
    }
}

/// Where now-playing info comes from and where controls go.
@MainActor
public protocol NowPlayingSource: AnyObject {
    /// Calls `onChange` whenever the track or play state changes.
    func observe(_ onChange: @escaping @MainActor (NowPlaying?) -> Void)
    /// Asks the running player directly (may trigger the Automation permission prompt once).
    func current() -> NowPlaying?
    func playPause(_ player: MusicPlayer?)
    func next(_ player: MusicPlayer?)
    func previous(_ player: MusicPlayer?)
    /// Brings the player's own window forward.
    func open(_ player: MusicPlayer?)
    /// Finds `query` by name and starts it; the reply says what happened, or that it couldn't.
    func play(_ query: String, in player: MusicPlayer) -> String
}
