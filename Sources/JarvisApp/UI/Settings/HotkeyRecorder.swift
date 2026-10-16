import AppKit
import Carbon.HIToolbox
import JarvisKit
import SwiftUI

/// Click, then press the new shortcut. Needs at least one of ⌃⌥⌘ so plain typing never triggers it.
struct HotkeyRecorder: View {
    let label: String
    @Binding var hotkey: Hotkey
    let fallback: Hotkey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(label) {
            HStack {
                Button(recording ? "Press keys…" : hotkey.text) {
                    recording ? stop() : start()
                }
                .monospaced()
                if hotkey != fallback {
                    Button("Reset") { hotkey = fallback }
                        .buttonStyle(.borderless)
                }
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])
            guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
            hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: Self.carbon(flags), key: Self.name(event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value = 0
        if flags.contains(.control) { value |= controlKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.shift) { value |= shiftKey }
        if flags.contains(.command) { value |= cmdKey }
        return UInt32(value)
    }

    private static func name(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        default: (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
