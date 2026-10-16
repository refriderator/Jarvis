import AVFoundation
import CoreAudio
import Speech

/// Turns speech into text while the user talks.
@MainActor
public protocol Listener: AnyObject {
    /// `onText` gets the transcript so far, again and again as it grows.
    func start(microphoneID: String?, onText: @escaping (String) -> Void) throws
    /// Stops listening and returns the final transcript.
    func finish() async -> String
}

/// Apple's speech recognition, kept on this Mac when the language supports it.
@MainActor
public final class SpeechListener: Listener {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var done = false

    public init() {}

    public func start(microphoneID: String?, onText: @escaping (String) -> Void) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw ChatError("Speech recognition isn't available for this language right now.")
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        if let microphoneID { Self.select(microphoneID, on: input) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.feed(request))
        engine.prepare()
        try engine.start()

        latest = ""
        done = false
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.results { [weak self] text, finished in
            guard let self else { return }
            if let text {
                latest = text
                onText(text)
            }
            if finished { done = true }
        })
    }

    // The audio tap and the recognizer call back on their own threads. Closures written inside this
    // main-actor class would be main-actor too, and Swift traps when they run elsewhere, so they are
    // made here, outside it, and hop to the main actor themselves.

    nonisolated private static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func results(
        _ update: @escaping @MainActor (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = result?.isFinal == true || error != nil
            Task { @MainActor in update(text, finished) }
        }
    }

    public func finish() async -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // The last words arrive a moment after the audio ends.
        for _ in 0..<20 where !done {
            try? await Task.sleep(for: .milliseconds(75))
        }
        task?.cancel()
        task = nil
        request = nil
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Points the engine at the chosen microphone. `AVCaptureDevice.uniqueID` is the Core Audio device UID.
    private static func select(_ uid: String, on input: AVAudioInputNode) {
        guard let unit = input.audioUnit else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        guard status == noErr, device != 0 else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &device, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}
