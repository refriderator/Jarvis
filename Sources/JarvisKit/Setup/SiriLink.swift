import Foundation

/// Siri reaches Jarvis through a shortcut the user makes once ("Ask Jarvis"): it dictates the question and opens
/// `jarvis://ask?q=<question>`. A link rather than App Intents: Jarvis is built without Xcode, and App Intents need
/// Xcode's build step to be found by Siri.
public enum SiriLink {
    public static let scheme = "jarvis"

    /// The question in a `jarvis://ask?q=...` link, or nil when it isn't one.
    public static func question(in url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "ask",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let text = items.first(where: { $0.name == "q" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// How to make the shortcut, for Settings › Features.
    public static let steps = [
        "In the Shortcuts app, make a new shortcut named Ask Jarvis.",
        "Add Dictate Text, then URL Encode (it encodes the Dictated Text), then Open URLs.",
        "In Open URLs, type jarvis://ask?q= and put the URL Encoded Text right after it.",
        "Then say \"Hey Siri, Ask Jarvis\" and your question. The answer is spoken from the notch.",
    ]

    /// How to make the alarm shortcut that `AlarmCommand` runs.
    public static let alarmSteps = [
        "In the Shortcuts app, make a new shortcut named Jarvis Alarm.",
        "Add Get Dates from Input (it reads the Shortcut Input), then Create Alarm with its time set to Dates.",
        "Then \"set an alarm for 7 am\" or \"wake me up at 6:30\" puts an alarm in the Clock app.",
    ]
}
