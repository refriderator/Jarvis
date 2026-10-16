import Foundation

/// What the Mac tools reach in the app: opening apps, the notch's window strip and Quick Dock. The tools are made
/// before the notch is, so the app fills these in once it's up; until then a call says it isn't ready.
/// Each returns what happened, for the model, or throws to say why it couldn't.
@MainActor
public final class MacControls {
    public var openApp: ((String) throws -> String)?
    /// Sets an app's front window aside in the notch; nil means the window in front.
    public var dockWindow: ((String?) throws -> String)?
    public var undockWindow: ((String) throws -> String)?
    public var setQuickDock: ((Bool) throws -> String)?

    public init() {}
}

/// Doing things on this Mac, as tools for the local brain: open an app, put a window in the notch's dock or bring it
/// back, and Quick Dock on or off. Values are checked here, not trusted.
public struct MacTools: ToolKit {
    public let name = "mac"
    private let controls: MacControls

    public init(controls: MacControls) {
        self.controls = controls
    }

    public var instructions: String { "Open apps, put windows in the notch's dock, and turn Quick Dock on or off." }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "open_app", description: "Open an app on this Mac by its name.",
                           schema: #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
            ToolDefinition(name: "dock_window", description: "Put an app's window in the notch's dock (set aside until clicked). Leave app out for the window in front.",
                           schema: #"{"type":"object","properties":{"app":{"type":"string"}}}"#),
            ToolDefinition(name: "undock_window", description: "Bring an app's window back out of the notch's dock.",
                           schema: #"{"type":"object","properties":{"app":{"type":"string"}},"required":["app"]}"#),
            ToolDefinition(name: "quick_dock", description: "Turn Quick Dock on or off (one window in front at a time, the rest wait in the notch's dock).",
                           schema: #"{"type":"object","properties":{"on":{"type":"boolean"}},"required":["on"]}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        let app = (input["app"] as? String ?? input["name"] as? String)?.trimmingCharacters(in: .whitespaces)
        let named = app.flatMap { $0.isEmpty ? nil : $0 }
        return try await MainActor.run {
            switch name {
            case "open_app":
                guard let named else { throw ChatError("name must be the app's name, like \"Spotify\".") }
                return try ready(controls.openApp)(named)
            case "dock_window":
                return try ready(controls.dockWindow)(named)
            case "undock_window":
                guard let named else { throw ChatError("app must be the app's name, like \"Safari\".") }
                return try ready(controls.undockWindow)(named)
            case "quick_dock":
                guard let on = input["on"] as? Bool else { throw ChatError("on must be true or false.") }
                return try ready(controls.setQuickDock)(on)
            default:
                throw ChatError("No tool named \(name).")
            }
        }
    }

    @MainActor
    private func ready<T>(_ control: T?) throws -> T {
        guard let control else { throw ChatError("That isn't ready yet: Jarvis is still starting.") }
        return control
    }
}
