import AVFoundation

/// A voice the user can pick in Settings.
public struct VoiceOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    /// "Premium", "Enhanced", "Personal" or "" for the default quality.
    public let quality: String
}

/// Installed Apple voices, best first. Personal Voice shows up once the user allows it.
public enum VoiceCatalog {
    public static func installed() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { rank($0) != rank($1) ? rank($0) > rank($1) : $0.name < $1.name }
            .map { voice in
                VoiceOption(id: voice.identifier, name: voice.name, language: voice.language, quality: label(voice))
            }
    }

    /// Asks for Personal Voice access; true if granted.
    public static func requestPersonalVoice() async -> Bool {
        await AVSpeechSynthesizer.requestPersonalVoiceAuthorization() == .authorized
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        if voice.voiceTraits.contains(.isPersonalVoice) { return 3 }
        return switch voice.quality {
        case .premium: 2
        case .enhanced: 1
        default: 0
        }
    }

    private static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "Personal" }
        return switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: ""
        }
    }
}
