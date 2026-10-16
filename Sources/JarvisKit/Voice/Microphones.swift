import AVFoundation

public struct MicrophoneOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

/// Audio inputs the user can pick in Settings.
public enum Microphones {
    public static func available() -> [MicrophoneOption] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices
            .map { MicrophoneOption(id: $0.uniqueID, name: $0.localizedName) }
    }
}
