import AVFoundation

/// Reads answers aloud.
@MainActor
public protocol Speaker: AnyObject {
    /// Called when speech ends, finished or stopped.
    var onFinish: (() -> Void)? { get set }
    func speak(_ text: String, voiceID: String?, rate: Double)
    func stop()
}

/// The installed Apple voices (including Premium and Personal Voice).
@MainActor
public final class SystemSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    public var onFinish: (() -> Void)?
    private let synthesizer = AVSpeechSynthesizer()

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String, voiceID: String?, rate: Double) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        // Settings keep 0...1 with 0.5 as normal, which is AVSpeechUtterance's own scale.
        utterance.rate = Float(rate)
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
