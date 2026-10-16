import Foundation

/// One question and what came back.
public struct Turn: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let question: String
    public let asked: Date
    public var answer: String?
    /// Who answered, e.g. "On-device" or "Claude Code · local unsure".
    public var source: String?
    public var tokens = 0
    public var failed = false
    /// Token saving is on and Jarvis is waiting for a yes before using the cloud brain.
    public var awaitingCloud = false
    /// Asked by voice (or a timer going off), so the answer is read aloud too.
    public var spoken = false
    /// When the answer arrived; the "last response" tab is offered for a minute after.
    public var answeredAt: Date?
    /// Answered by the cloud brain (Claude), so it can be summarized.
    public var cloud = false
    /// The answer as points (the caption's Summarize button); nil until asked for.
    public var summary: Summary?
    public var summarizing = false

    public init(question: String, asked: Date = .now, spoken: Bool = false) {
        self.question = question
        self.asked = asked
        self.spoken = spoken
    }

    public var isPending: Bool { answer == nil && !awaitingCloud }
}
