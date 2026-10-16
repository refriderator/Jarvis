import JarvisKit
import SwiftUI

/// The slim menu-bar menu: Talk / Type · Stop talking · Timers · Skin · Tokens · Settings · Quit.
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
        Picker("Skin", selection: state.binding(\.skinID)) {
            ForEach(SkinCatalog.all) { skin in
                Text(skin.name).tag(skin.id)
            }
        }
        if state.settings.showTokens {
            Divider()
            Text("Tokens today: \(state.tokens.today.formatted())")
        }
        Picker("Open the Notch On", selection: state.binding(\.openTrigger)) {
            Text("Click (hover peeks)").tag(OpenTrigger.click)
            Text("Hover").tag(OpenTrigger.hover)
        }
        Divider()
        Toggle("Quick Dock", isOn: Binding(get: { state.settings.quickDock }, set: { on in state.update { $0.quickDock = on } }))
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Button("Quit Jarvis") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
