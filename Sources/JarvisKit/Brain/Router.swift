import Foundation

/// Decides who answers, with plain rules (asking a model to decide would cost more than it saves).
/// Local first: everything stays on this Mac except anything recent; the local model itself hands on
/// big changes and long writing by answering ESCALATE. Otherwise small questions stay and Notion, writing,
/// code and deep questions go to Claude.
public enum Router {
    public enum Route: Equatable, Sendable {
        case local
        case cloud
    }

    public struct Decision: Equatable, Sendable {
        public var route: Route
        /// The question without a leading "Claude," that forced the cloud.
        public var question: String
        /// The user named Claude, so they already chose the cloud.
        public var namedClaude: Bool

        public init(route: Route, question: String, namedClaude: Bool = false) {
            self.route = route
            self.question = question
            self.namedClaude = namedClaude
        }
    }

    private static let namedClaude = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:hey|ok|okay)[\s,]+)?(?:ask\s+)?claude\b[\s,.!?:;-]*"#, options: .caseInsensitive)

    private static let bigTask = try! NSRegularExpression(
        pattern: #"\b(notion|edit|update|rewrite|write|draft|email|essay|code|program|script|debug|"# +
            #"research|compare|summari[sz]e|translate|explain why|in detail|step by step|"# +
            #"derive|prove|solve|equation|integral|derivative|calculate)\b"#,
        options: .caseInsensitive)

    /// Local models only know their training data, so anything recent always goes to the cloud.
    private static let recent = try! NSRegularExpression(
        pattern: #"\b(latest|recent|news|score|who won|stock|price of|election|last night|yesterday|tonight|this week|weather)\b"#,
        options: .caseInsensitive)

    /// Longer than this many words is treated as a big question.
    public static let longQuestionWords = 30

    /// `hasTools`: the question is answered from the user's own data (Notion, calendar, timers), so words
    /// like "this week" or "yesterday" don't mean the model needs news it doesn't have.
    public static func decide(_ text: String, localAvailable: Bool, preferLocal: Bool = false,
                              hasTools: Bool = false) -> Decision {
        let range = NSRange(text.startIndex..., in: text)
        if let match = namedClaude.firstMatch(in: text, range: range), let end = Range(match.range, in: text) {
            let rest = text[end.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return Decision(route: .cloud, question: rest, namedClaude: true) }
        }
        let isRecent = !hasTools && recent.firstMatch(in: text, range: range) != nil
        let big = !preferLocal && (bigTask.firstMatch(in: text, range: range) != nil
            || text.split(whereSeparator: \.isWhitespace).count > longQuestionWords)
        return Decision(route: localAvailable && !isRecent && !big ? .local : .cloud, question: text)
    }

    /// The local model's way of saying "ask Claude". It sometimes tacks the word onto
    /// a guess, so anywhere in the reply counts.
    public static func isEscalation(_ reply: String) -> Bool {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.uppercased().contains(Persona.escalate)
    }
}
