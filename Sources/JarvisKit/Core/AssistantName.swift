import Foundation

/// What the assistant is called (Settings › General, or the welcome's first step). It's what the assistant calls
/// itself to the cloud brain and what the notch shows; the app is still Jarvis. Some names get in the way of how
/// questions are understood, so `warnings` says why before one is picked.
public enum AssistantName {
    public static let standard = "Jarvis"

    /// The name to use: what was typed, tidied, or Jarvis when it's empty.
    public static func display(_ typed: String) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? standard : name
    }

    /// Why a name might confuse it; empty when it looks fine.
    public static func warnings(for typed: String) -> [String] {
        let name = display(typed)
        let lower = name.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        var found: [String] = []
        if words.contains("claude") {
            found.append("Starting a question with \u{201C}Claude,\u{201D} sends it straight to the cloud brain, so every question "
                         + "that starts with this name would skip the free local model.")
        }
        if !words.isDisjoint(with: otherAssistants) {
            found.append("That's another assistant's name: saying it out loud can wake a phone or speaker nearby.")
        }
        if let word = words.first(where: commandWords.contains) {
            found.append("\u{201C}\(word.capitalized)\u{201D} is a word Jarvis acts on, so a question that starts with the name "
                         + "could be taken as a command.")
        }
        if name.count <= 2 {
            found.append("Very short names are easy for speech recognition to mishear or miss.")
        } else if name.count > 20 {
            found.append("Long names are tiring to say before every question.")
        }
        if name.contains(where: { $0.isNumber || ($0.isSymbol || $0.isPunctuation) && $0 != "-" && $0 != "'" }) {
            found.append("Numbers and symbols come out of speech recognition spelled differently, so a spoken name won't match.")
        }
        return found
    }

    /// A question that starts by addressing the assistant ("Hey Nova, set a timer") without that part, so the
    /// name isn't taken as part of the question.
    public static func dropAddress(_ question: String, name typed: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: display(typed))
        guard let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:(?:hey|hi|ok|okay)[\s,]+)?"# + name + #"\b[\s,.!?:;-]*"#, options: .caseInsensitive)
        else { return question }
        let range = NSRange(question.startIndex..., in: question)
        guard let match = pattern.firstMatch(in: question, range: range), match.range.length < range.length else { return question }
        return String(question[Range(match.range, in: question)!.upperBound...])
    }

    private static let otherAssistants: Set = ["siri", "alexa", "google", "cortana", "bixby", "gemini", "chatgpt", "copilot"]
    private static let commandWords: Set = [
        "timer", "remind", "reminder", "alarm", "cancel", "stop", "calendar", "notion", "open", "play", "pause",
        "next", "music", "weather", "escalate", "search", "today", "tomorrow",
    ]
}
