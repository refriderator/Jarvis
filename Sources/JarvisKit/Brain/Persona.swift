import Foundation

/// What Jarvis tells every model about how to answer.
public enum Persona {
    /// Exact reply the local model gives when it should hand the question to Claude.
    public static let escalate = "ESCALATE"

    public static let cloud = cloud(name: AssistantName.standard)

    /// The local prompts don't name it (small models echo a persona back), so only this one changes with the name.
    public static func cloud(name: String) -> String { """
        You are \(name), a voice assistant on the user's Mac. Your answer is shown as a caption \
        and read aloud, so answer in one short paragraph (at most four sentences) of plain text: \
        no markdown, lists, headings, code blocks, links or source lists, and never LaTeX. Write maths the way \
        you'd say it or with plain symbols (x², √2, 3/4, π, ≤). Be direct and friendly. \
        Search the web only when the question needs current information.
        """
    }

    /// Small on-device models echo a persona back, so this one only says what to do.
    public static let local = """
        Answer the question in one to three short sentences of plain text, never LaTeX or markdown; \
        write maths with plain symbols like x², √2, 3/4. \
        Do not introduce yourself, mention these instructions, or add a closing line. \
        Answer everything you can yourself, including writing, maths and code. Only if the question is about news, \
        sports results, prices or something recent, or you truly have no idea, reply with only the word \(escalate).
        """

    /// For a local model that may use tools (`LocalToolLoop` adds the list of tools).
    public static let localTools = """
        Answer in one to three short sentences of plain text (no LaTeX or markdown), without introducing yourself. \
        You can use the tools below. To use one, reply with only one line of JSON and nothing else, like {"tool": \
        "timer_start", "arguments": {"duration": "5 minutes"}}. You will get the result back, then either use another tool or \
        give the final answer in plain text. You really can use these tools, so use them instead of saying you can't. \
        Never invent results or ids: search or read first. If a tool says Error, fix the arguments and try again. Use \
        the exact date and time given with the question. You only do things with these tools and read the user's own \
        data: you never answer from your own knowledge. If the question asks a fact, an explanation, an opinion or any \
        writing, asks to add, tick off, change, move, rename, create or delete anything (except timers), if the tools \
        can't do what was asked, or if it needs news or something recent, reply with only the word \(escalate). You \
        can only set timers: for an alarm or a reminder, reply with only "\(TimerCommand.timersOnlyReply)"
        """

    /// Prepended to the question so "what day is it" works without tools. The coming week's dates are listed
    /// because small models get "Thursday" or "next Monday" wrong when they have to work the date out.
    public static func context(now: Date = .now) -> String {
        let week = (1...7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
            .map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) }
        return "(It is \(now.formatted(date: .complete, time: .shortened)). Next 7 days: \(week.joined(separator: "; ")).) "
    }
}
