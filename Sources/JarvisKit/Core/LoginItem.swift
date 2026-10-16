import ServiceManagement

/// Starts Jarvis when the user logs in.
public protocol LoginItem: Sendable {
    /// Returns whether it is enabled afterwards (registration can fail).
    @MainActor func setEnabled(_ enabled: Bool) -> Bool
}

public struct SystemLoginItem: LoginItem {
    public init() {}

    @MainActor public func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            // Fall through and report the real state.
        }
        return service.status == .enabled
    }
}

/// Does nothing; for tests.
public struct NoLoginItem: LoginItem {
    public init() {}
    @MainActor public func setEnabled(_ enabled: Bool) -> Bool { enabled }
}
