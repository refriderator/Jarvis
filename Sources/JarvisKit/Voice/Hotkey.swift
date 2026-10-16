import Carbon.HIToolbox

/// A global shortcut: a key plus Carbon modifier flags, with the key's name for display.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// The key's own name, e.g. "Space" or "J".
    public var key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public static let talk = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")
    public static let type = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), key: "Space")
    public static let stop = Hotkey(keyCode: UInt32(kVK_Escape), modifiers: 0, key: "esc")

    /// "⌥⇧Space"
    public var text: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }
}
