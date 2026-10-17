import Foundation

/// Work on text that's already on screen: summarizing the page or the selection, or rewriting the selection. Apple
/// Intelligence's job (free, private, good at exactly this), so the local Qwen never needs to learn it. Read by code
/// from the wording; asked without "this page" or "the selection" ("summarize the French revolution"), it's an
/// ordinary question for the brains.
public enum TextJob: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case page
        case selection
        /// "summarize this": the selection if there is one, else the page.
        case either
    }

    case summarize(Target)
    /// Rewrites the selection as asked ("proofread this", "make the selection more formal").
    case rewrite(instruction: String)

    private static let summarizeWords = #"\b(summari[sz]e|sum up|tl;?dr|give me the gist|the gist of|what('?s| is) (this|the) (page|article|post) (about|saying))\b"#
    private static let pageWords = #"\b(this|the|that|current) (page|article|website|site|tab|post|story)\b"#
    private static let selectionWords = #"\b(selection|selected|highlighted|what i('ve)? (selected|highlighted)|this text)\b"#
    private static let rewriteWords = #"\b(proofread|fix (the )?(grammar|spelling|typos)|rewrite|rephrase|reword|make (it|this|the selection|that|the text) (shorter|longer|clearer|simpler|more \w+|less \w+|sound \w+)|shorten)\b"#

    public static func parse(_ text: String) -> TextJob? {
        let lower = text.lowercased()
        let page = matches(lower, pageWords)
        let selection = matches(lower, selectionWords)
        if matches(lower, summarizeWords) {
            if selection { return .summarize(.selection) }
            if page { return .summarize(.page) }
            // "summarize this", "summarize it", "tldr": only when that's all there is.
            if lower.range(of: #"^\W*(please\s+)?(summari[sz]e|sum up|tl;?dr)(\s+(this|it|that))?(\s+(for me|please))?\W*$"#,
                           options: .regularExpression) != nil { return .summarize(.either) }
            return nil
        }
        // A rewrite needs the selection (or "this", which means it). "Make it shorter" is about the last answer.
        if matches(lower, rewriteWords), selection || matches(lower, #"\bthis\b"#), !page {
            return .rewrite(instruction: text)
        }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: Prompts

    static let summarySystem = """
        You summarize text for someone who will hear it read aloud. Use at most four short sentences of plain words: no \
        markdown, lists or links. Say what it is and its main points. Use only the text you are given.
        """
    static let partSystem = """
        You summarize one part of a longer text. Use at most three short sentences of plain words. Use only the text \
        you are given.
        """
    static let rewriteSystem = """
        You rewrite the user's text as they ask. Reply with only the rewritten text: no introduction, quotes or notes. \
        Keep its meaning, and its language unless asked to change it.
        """

    /// About 2,000 tokens a part: Apple's on-device model reads about 4,000 at once, prompt and answer included.
    static let partChars = 7000
    /// Past this many parts the rest is left out, so a huge page still answers in seconds.
    static let maxParts = 6

    /// The text cut at paragraph breaks into parts small enough for the on-device model.
    static func parts(_ text: String) -> [String] {
        var parts: [String] = [], current = ""
        for paragraph in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !paragraph.isEmpty {
            var rest = Substring(paragraph)
            while !rest.isEmpty {
                let room = partChars - current.count
                if rest.count <= room {
                    current += (current.isEmpty ? "" : "\n") + rest
                    rest = ""
                } else if current.isEmpty {
                    current = String(rest.prefix(partChars))
                    rest = rest.dropFirst(partChars)
                } else {
                    parts.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    /// A spoken summary: one call for a short text, else each part summarized, then those summaries summarized.
    @MainActor
    static func summarize(_ text: String, title: String, with model: ChatProvider) async throws -> (text: String, cut: Bool) {
        let all = parts(text)
        let used = Array(all.prefix(maxParts))
        let heading = title.isEmpty ? "" : "Title: \(title)\n\n"
        guard used.count > 1 else {
            let reply = try await model.reply(system: summarySystem, history: [ChatMessage(.user, heading + (used.first ?? ""))])
            return (reply.text, false)
        }
        var notes: [String] = []
        for part in used {
            notes.append(try await model.reply(system: partSystem, history: [ChatMessage(.user, part)]).text)
        }
        let reply = try await model.reply(system: summarySystem,
                                          history: [ChatMessage(.user, heading + notes.joined(separator: "\n\n"))])
        return (reply.text, all.count > used.count)
    }

    @MainActor
    static func rewrite(_ text: String, instruction: String, with model: ChatProvider) async throws -> String {
        let prompt = "Request: \(instruction)\n\nText:\n\(String(text.prefix(partChars)))"
        return try await model.reply(system: rewriteSystem, history: [ChatMessage(.user, prompt)]).text
    }
}
