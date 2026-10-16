import Carbon.HIToolbox

/// Global shortcuts through Carbon's hot key API: works in the background with no special permission,
/// and reports key release too (needed for push-to-hold).
@MainActor
public final class Hotkeys {
    public enum Slot: UInt32 {
        case talk = 1, type, stop
    }

    private struct Handler {
        let press: () -> Void
        let release: (() -> Void)?
    }

    private static let signature: OSType = 0x4A52_5653 // "JRVS"
    private var refs: [Slot: EventHotKeyRef] = [:]
    private var handlers: [Slot: Handler] = [:]
    private var eventHandler: EventHandlerRef?

    public init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let hotkeys = Unmanaged<Hotkeys>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { hotkeys.fire(id.id, pressed: pressed) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Replaces whatever was in `slot`. Returns false if macOS refused (another app owns the shortcut).
    @discardableResult
    public func register(_ slot: Slot, _ hotkey: Hotkey, press: @escaping () -> Void,
                         release: (() -> Void)? = nil) -> Bool {
        unregister(slot)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: slot.rawValue),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[slot] = ref
        handlers[slot] = Handler(press: press, release: release)
        return true
    }

    public func unregister(_ slot: Slot) {
        if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
        handlers[slot] = nil
    }

    private func fire(_ id: UInt32, pressed: Bool) {
        guard let slot = Slot(rawValue: id), let handler = handlers[slot] else { return }
        if pressed { handler.press() } else { handler.release?() }
    }
}
