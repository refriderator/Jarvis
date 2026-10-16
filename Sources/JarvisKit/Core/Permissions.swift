import AVFoundation
import EventKit
import Foundation
import Speech

public enum Permission: String, Sendable, CaseIterable, Identifiable {
    case microphone, speech, camera, calendar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .speech: "Speech Recognition"
        case .camera: "Camera"
        case .calendar: "Calendar"
        }
    }

    public var reason: String {
        switch self {
        case .microphone: "So you can talk to Jarvis."
        case .speech: "Turns what you say into text, on this Mac."
        case .camera: "Only when you ask Jarvis to look at something."
        case .calendar: "Lets Jarvis read and add events."
        }
    }

    /// The matching pane in System Settings, for when access was denied.
    public var settingsURL: URL? {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .speech: "Privacy_SpeechRecognition"
        case .camera: "Privacy_Camera"
        case .calendar: "Privacy_Calendars"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }
}

public enum PermissionStatus: Sendable {
    case notAsked, granted, denied
}

public protocol PermissionChecking: Sendable {
    func status(_ permission: Permission) -> PermissionStatus
    func request(_ permission: Permission) async -> PermissionStatus
}

/// Asks macOS. Needs the usage strings in Info.plist, or macOS kills the app on request.
public struct SystemPermissions: PermissionChecking {
    public init() {}

    public func status(_ permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone: Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera: Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .notDetermined: .notAsked
            case .authorized: .granted
            default: .denied
            }
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .notDetermined: .notAsked
            case .fullAccess: .granted
            default: .denied
            }
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .speech:
            await withCheckedContinuation { done in
                SFSpeechRecognizer.requestAuthorization { _ in done.resume() }
            }
        case .calendar: _ = try? await EKEventStore().requestFullAccessToEvents()
        }
        return status(permission)
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notAsked
        case .authorized: .granted
        default: .denied
        }
    }
}
