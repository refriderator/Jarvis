import Foundation

/// The apps-and-music fast path: plainly worded "open Spotify", "play X on Apple Music", "next song" read by
/// code, no model. It only claims a request when the whole sentence fits; anything looser ("open my notion
/// and tell me what's due", "play devil's advocate") is left to a brain, which can ask or look things up.
public enum AppCommand: Equatable, Sendable {
    case open(app: String)
    /// `app` is nil when the request didn't name one: the music app that is already open is used.
    case play(query: String, app: String?)
    case control(Control)

    public enum Control: Equatable, Sendable {
        case pause, resume, next, previous
    }

    private static let lead = #"^\s*(?:(?:hey|ok|okay)[,\s]+)?(?:(?:please|can you|could you)\s+)?"#
    private static let tail = #"\s*(?:please)?\s*[.!?]*\s*$"#

    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: lead + pattern + tail, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    public static func parse(_ text: String) -> AppCommand? {
        if let words = capture(#"(?:open|launch|start|run)(?:\s+up)?\s+(?:the\s+)?([\w.&+' -]{1,40}?)(?:\s+app)?"#, in: text) {
            let name = words[0].trimmingCharacters(in: .whitespaces)
            // App names are short; a longer phrase is a request with more in it ("open my notion and tell me what's due").
            return name.split(separator: " ").count <= 4 ? .open(app: name) : nil
        }
        let object = #"(?:\s+(?:the\s+)?(?:music|song|track|playback|spotify|apple music))?"#
        if capture(#"(?:pause|stop)"# + object, in: text) != nil, !text.lowercased().contains("stop") || mentionsMusic(text) {
            return .control(.pause)
        }
        if capture(#"(?:resume|unpause)"# + object, in: text) != nil { return .control(.resume) }
        if capture(#"(?:next|skip(?:\s+to\s+the\s+next)?)\s+(?:the\s+|this\s+)?(?:song|track)"#, in: text) != nil { return .control(.next) }
        if capture(#"(?:previous|last|go back to the previous)\s+(?:the\s+)?(?:song|track)"#, in: text) != nil { return .control(.previous) }
        // "play X on Spotify" / "play X on Apple Music", or "play X" for the music app already open.
        if let words = capture(#"play\s+(.{1,80}?)\s+(?:on|in|with)\s+(spotify|apple music|music)"#, in: text) {
            return .play(query: clean(words[0]), app: words[1].lowercased() == "spotify" ? "Spotify" : "Music")
        }
        if let words = capture(#"play\s+(.{1,80}?)"#, in: text), !notMusic(words[0]) {
            return .play(query: clean(words[0]), app: nil)
        }
        return nil
    }

    private static func mentionsMusic(_ text: String) -> Bool {
        text.range(of: #"\b(music|song|track|playback|spotify)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func clean(_ query: String) -> String {
        query.replacingOccurrences(of: #"^(?:the\s+)?(?:song|track|album|playlist|artist)\s+"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// "play it", "play a game", "play devil's advocate": not a song request, so a brain answers instead.
    private static func notMusic(_ query: String) -> Bool {
        let lower = query.lowercased()
        if lower.range(of: #"^(?:it|that|this|something|anything|some music|music|a song|again)\b"#, options: .regularExpression) != nil {
            return true
        }
        return lower.range(of: #"\b(game|games|chess|with|against|along|dumb|fair|around|catch|tricks?|role|part|devil|trump)\b"#,
                           options: .regularExpression) != nil
    }
}
