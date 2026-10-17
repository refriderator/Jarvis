import Foundation

/// The user's shortcuts (the Shortcuts app), run with macOS's `shortcuts` command. Reaches what only Apple's apps can
/// do, like a Clock alarm, without Jarvis needing an API for each.
public protocol ShortcutRunner: Sendable {
    /// The names of the user's shortcuts.
    func names() async -> [String]
    /// Runs one with `input` as its text input; its text output, if any.
    func run(_ name: String, input: String?) async throws -> String
}

public struct MacShortcuts: ShortcutRunner {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public init() {}

    public func names() async -> [String] {
        let output = try? await ProcessRunner.run(Self.tool, arguments: ["list"], environment: Self.environment,
                                                  directory: FileManager.default.temporaryDirectory, input: "", timeout: 10)
        return output.map { String(decoding: $0.stdout, as: UTF8.self).split(separator: "\n").map(String.init) } ?? []
    }

    public func run(_ name: String, input: String?) async throws -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jarvis-shortcuts")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appending(path: "output.txt")
        try? FileManager.default.removeItem(at: output)
        var arguments = ["run", name, "--output-path", output.path, "--output-type", "public.plain-text"]
        if let input {
            let file = folder.appending(path: "input.txt")
            try input.write(to: file, atomically: true, encoding: .utf8)
            arguments += ["--input-path", file.path]
        }
        let result = try await ProcessRunner.run(Self.tool, arguments: arguments, environment: Self.environment,
                                                 directory: folder, input: "", timeout: 60)
        guard result.status == 0 else { throw ChatError("The \(name) shortcut didn't finish.") }
        return (try? String(contentsOf: output, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var environment: [String: String] {
        let env = ProcessInfo.processInfo.environment
        return ["HOME": env["HOME"] ?? NSHomeDirectory(), "USER": env["USER"] ?? NSUserName(), "PATH": "/usr/bin:/bin"]
    }
}

/// "run my focus shortcut", "run the shortcut Morning": the shortcut's name as said, matched against the real ones.
public enum ShortcutCommand {
    public static func name(in text: String) -> String? {
        let patterns = [#"^\s*(?:please\s+)?(?:run|start|do)\s+(?:the\s+|my\s+)?shortcut\s+(?:called\s+|named\s+)?(.+?)[.!?]*$"#,
                        #"^\s*(?:please\s+)?(?:run|start|do)\s+(?:the\s+|my\s+)?(.+?)\s+shortcut[.!?]*$"#]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let found = Range(match.range(at: 1), in: text) {
                return String(text[found]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”"))
            }
        }
        return nil
    }

    /// The real shortcut a spoken name means: exact, ignoring case and punctuation.
    public static func match(_ said: String, in names: [String]) -> String? {
        let key = { (name: String) in name.lowercased().filter { $0.isLetter || $0.isNumber } }
        return names.first { key($0) == key(said) }
    }
}

/// Alarms: macOS gives apps no way to set a Clock alarm, but the Shortcuts app's "Create Alarm" action can, so Jarvis
/// runs the user's "Jarvis Alarm" shortcut with the time. Without it, Jarvis says how to make it.
public enum AlarmCommand: Equatable, Sendable {
    case set(SpokenTime)
    /// Cancelling or turning one off: that's the Clock app's.
    case off
    case unclear

    public static let shortcutName = "Jarvis Alarm"
    public static let needsShortcut = """
        Alarms go to the Clock app through a shortcut called "Jarvis Alarm". Settings › Features › Reminders and \
        alarms shows how to make it.
        """
    public static let offReply = "Turn alarms off in the Clock app."
    public static let unclearReply = "What time? Try \"set an alarm for 7 am\"."

    public static func parse(_ text: String) -> AlarmCommand? {
        let lower = text.lowercased()
        guard lower.range(of: #"\b(alarms?|wake me)\b"#, options: .regularExpression) != nil else { return nil }
        if lower.range(of: #"^(what|which|show|list|do i have|any)\b"#, options: .regularExpression) != nil { return nil }
        if lower.range(of: #"\b(cancel|stop|clear|delete|remove|turn off|disable|snooze)\b"#, options: .regularExpression) != nil {
            return .off
        }
        guard let time = SpokenTime.parse(lower), time != .day(tomorrow: true) else { return .unclear }
        return .set(time)
    }
}
