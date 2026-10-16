import JarvisKit
import SwiftUI

/// The slim menu-bar menu: Talk / Type · Stop talking · Quick Dock · Skin · Open on · Display · Timers · Settings · Quit.
struct JarvisMenu: View {
    let state: AppState
    let voice: VoiceSession?
    let timers: TimerCenter
    let openSettings: () -> Void

    var body: some View {
        Button(state.voice.isListening ? "Stop Listening" : "Talk  \(state.settings.talkHotkey.text)") {
            voice?.toggleTalk()
        }
        Button("Type  \(state.settings.typeHotkey.text)") { state.send(.summon) }
        if state.voice == .speaking {
            Button("Stop Talking") { voice?.stopSpeaking() }
        }
        Toggle("Quick Dock", isOn: Binding(get: { state.settings.quickDock }, set: { on in state.update { $0.quickDock = on } }))
        Divider()
        Picker("Skin", selection: state.binding(\.skinID)) {
            ForEach(SkinCatalog.all) { skin in
                Text(skin.name).tag(skin.id)
            }
        }
        Picker("Open the Notch On", selection: state.binding(\.openTrigger)) {
            Text("Click (hover peeks)").tag(OpenTrigger.click)
            Text("Hover").tag(OpenTrigger.hover)
        }
        DisplayPicker(state: state, title: "Notch On")
        if !state.timers.isEmpty {
            Divider()
            Menu("Timers") {
                ForEach(state.timers) { timer in
                    Button("Cancel \(timer.label) timer (ends \(timer.ends.formatted(date: .omitted, time: .shortened)))") {
                        timers.cancel(timer.id)
                    }
                }
                if state.timers.count > 1 {
                    Divider()
                    Button("Cancel All", action: timers.cancelAll)
                }
            }
        }
        Divider()
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Button("Quit Jarvis") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Which plugged-in display the notch is on. It shows where the notch really is: a picked display that's
/// unplugged shows as the Mac's own, and the notch goes back to it once it's plugged in again.
struct DisplayPicker: View {
    let state: AppState
    let title: String

    var body: some View {
        let screens = NSScreen.screens
        let current = state.notchScreen
        Picker(title, selection: Binding(
            get: { current.map { $0.isBuiltIn ? "" : $0.key } ?? "" },
            set: { key in state.update { $0.notchDisplay = key } })) {
            ForEach(screens, id: \.key) { screen in
                Text(screen.title).tag(screen.isBuiltIn ? "" : screen.key)
            }
        }
    }
}
