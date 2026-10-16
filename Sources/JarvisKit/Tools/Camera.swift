import AVFoundation
import Foundation

/// Takes one photo with the Mac's camera, only when the user asks Jarvis to look.
@MainActor
public protocol CameraSource {
    /// A JPEG.
    func snapshot() async throws -> Data
}

@MainActor
public final class MacCamera: NSObject, CameraSource, AVCapturePhotoCaptureDelegate {
    /// Lets exposure and white balance settle before the shot.
    private static let warmUp: Duration = .milliseconds(900)
    private var continuation: CheckedContinuation<Data, Error>?

    override public init() {}

    nonisolated public static func matches(_ text: String) -> Bool {
        text.range(of: #"\b(look at|take a look|what (do|can) you see|what am i (holding|wearing|doing)|how do i look|"#
                   + #"can you see|use the camera|camera|take a (photo|picture))\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    public func snapshot() async throws -> Data {
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized,
           !(await AVCaptureDevice.requestAccess(for: .video)) {
            throw ChatError("Jarvis needs Camera access. Allow it in System Settings › Privacy & Security › Camera.")
        }
        guard let device = AVCaptureDevice.default(for: .video) else { throw ChatError("No camera found.") }
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        let output = AVCapturePhotoOutput()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw ChatError("The camera is busy.") }
        session.addInput(input)
        session.addOutput(output)
        nonisolated(unsafe) let running = session
        await Task.detached { running.startRunning() }.value
        defer { Task.detached { running.stopRunning() } }
        try await Task.sleep(for: Self.warmUp)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
        }
    }

    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                                        error: Error?) {
        let result: Result<Data, Error> = photo.fileDataRepresentation().map { .success($0) }
            ?? .failure(error ?? ChatError("The camera didn't return a photo."))
        Task { @MainActor in
            self.continuation?.resume(with: result)
            self.continuation = nil
        }
    }
}
