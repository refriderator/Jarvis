/// What Jarvis's voice is doing right now.
public enum VoiceStatus: Equatable, Sendable {
    case idle
    /// Listening, with what it has heard so far.
    case listening(String)
    case speaking

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}
