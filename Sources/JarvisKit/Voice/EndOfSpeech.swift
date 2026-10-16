import Foundation

/// Decides when the user has stopped talking: a pause after they said something, or never saying anything.
/// Watches the transcript rather than the audio, so room noise and typing don't keep it listening.
public struct EndOfSpeech: Equatable, Sendable {
    /// How long the transcript may sit unchanged after speech before listening ends.
    public var pause: TimeInterval
    /// How long to wait for the first word before giving up.
    public var waitForSpeech: TimeInterval
    /// Never listens longer than this, so a stuck mic can't run forever.
    public var longest: TimeInterval

    private let started: Date
    private var lastText = ""
    private var lastChange: Date

    public init(pause: TimeInterval, waitForSpeech: TimeInterval = 8, longest: TimeInterval = 90, now: Date = .now) {
        self.pause = pause
        self.waitForSpeech = waitForSpeech
        self.longest = longest
        started = now
        lastChange = now
    }

    /// The transcript so far; each change counts as speech.
    public mutating func heard(_ text: String, now: Date = .now) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastText else { return }
        lastText = trimmed
        lastChange = now
    }

    public func shouldStop(now: Date = .now) -> Bool {
        if now.timeIntervalSince(started) >= longest { return true }
        if lastText.isEmpty { return now.timeIntervalSince(started) >= waitForSpeech }
        return now.timeIntervalSince(lastChange) >= pause
    }
}
