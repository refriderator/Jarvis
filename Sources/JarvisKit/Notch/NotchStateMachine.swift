/// What the notch is showing right now.
public enum NotchMode: Sendable {
    /// Matches the hardware notch (or a small pill on Macs without one).
    case idle
    /// Pointer is over the notch: it grows a little to show Jarvis is there.
    case peek
    /// Full panel with the input bar.
    case open
}

/// How the notch opens when the pointer reaches it.
public enum OpenTrigger: String, Sendable, CaseIterable {
    /// Hovering opens it.
    case hover
    /// Hovering only peeks; a click opens it.
    case click
}

public enum NotchEvent: Sendable {
    case pointerEntered
    case pointerExited
    case click(inside: Bool)
    /// Opened from the menu, a hotkey, or a reply arriving.
    case summon
    /// Esc, or something finished.
    case dismiss
}

/// Pure idle/peek/open logic. The app feeds it pointer events; the views draw `mode`.
/// However it opened, the panel closes when the pointer leaves it, a click lands outside, or Esc.
public struct NotchStateMachine: Sendable, Equatable {
    public private(set) var mode: NotchMode = .idle
    public var trigger: OpenTrigger
    /// A caption is up: the pointer leaving no longer closes the panel (a click outside or Esc still does).
    public var holdOpen = false
    /// A window is held in the open notch: neither the pointer leaving nor a click outside closes it, only a
    /// dismiss (the app tucks the window away first when Keep is off).
    public var locked = false
    /// Hovering opens even with the click trigger: nothing can be clicked mid-drag, and a tucked window
    /// comes back on hover.
    public var openOnHover = false
    /// Open because of a `summon` (the type shortcut, the menu, a reply), not the pointer: only then does opening
    /// take the keyboard, so you can type at once.
    public private(set) var summoned = false

    public init(trigger: OpenTrigger = .click) {
        self.trigger = trigger
    }

    public mutating func handle(_ event: NotchEvent) {
        let was = mode
        defer {
            if mode != .open { summoned = false } else if was != .open { summoned = { if case .summon = event { true } else { false } }() }
        }
        switch (event, mode) {
        case (.pointerExited, .open) where holdOpen || locked, (.click(inside: false), .open) where locked:
            break
        case (.pointerEntered, .idle):
            mode = trigger == .hover || openOnHover ? .open : .peek
        case (.pointerEntered, .peek) where openOnHover:
            mode = .open
        case (.pointerExited, .peek), (.pointerExited, .open), (.click(inside: false), .open), (.dismiss, _):
            mode = .idle
        case (.click(inside: true), .idle), (.click(inside: true), .peek), (.summon, _):
            mode = .open
        default:
            break
        }
    }
}
