import Foundation

/// Who answered a turn, for the caption: Jarvis (its own code or its local model), Siri (Apple's apps: Reminders,
/// Clock, Shortcuts), Apple Intelligence, or the cloud brain (Claude, or Codex...). Read from the turn's source, so
/// a confident answer from the small local model is never mistaken for Claude's.
public struct Answerer: Equatable, Sendable {
    public var name: String
    /// What exactly: "Timer", "Qwen3 8B", "Reminders", "local unsure"... Nil when the name says it all.
    public var detail: String?
    public var icon: String

    public var text: String { detail.map { "\(name) · \($0)" } ?? name }

    static let appleApps: Set<String> = ["Reminders", "Alarm", "Shortcuts"]

    public static func of(_ turn: Turn) -> Answerer? {
        guard let source = turn.source, turn.answer != nil, !turn.failed else { return nil }
        // "Claude Code · local unsure": the brain, then why it was asked.
        let parts = source.components(separatedBy: " · ")
        let brain = parts[0]
        let note = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : nil
        if turn.cloud {
            return Answerer(name: brain.hasPrefix("Claude") ? "Claude" : brain, detail: note, icon: "cloud.fill")
        }
        if brain == Assistant.onDeviceSource || brain == "On-device" {
            return Answerer(name: "Apple Intelligence", detail: nil, icon: "sparkles")
        }
        if appleApps.contains(brain) {
            return Answerer(name: "Siri", detail: brain == "Alarm" ? "Clock" : brain, icon: "apple.logo")
        }
        return Answerer(name: "Jarvis", detail: brain, icon: "gearshape.fill")
    }
}
