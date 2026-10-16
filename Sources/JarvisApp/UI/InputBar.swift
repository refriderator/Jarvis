import JarvisKit
import SwiftUI

/// Search-style field: magnifier, big rounded text, mic. Return asks Jarvis; the mic starts and stops listening.
struct InputBar: View {
    let state: AppState
    let assistant: Assistant
    let voice: VoiceSession
    @FocusState private var focused: Bool

    var body: some View {
        let skin = state.skin
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .opacity(0.45)
            TextField("", text: Binding(get: { state.draft }, set: { state.setDraft($0) }),
                      prompt: Text("Ask \(AssistantName.display(state.settings.assistantName))").foregroundStyle(skin.foreground.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .focused($focused)
                .onSubmit { assistant.ask(state.draft) }
            Button(action: voice.toggleTalk) {
                Image(systemName: state.voice.isListening ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 17))
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.voice.isListening ? Color.red : skin.accent)
            .help("Talk (\(state.settings.talkHotkey.text))")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        // On the Finder and Monitor tabs, typing waits for a click on the field.
        .onAppear { focused = state.dock.tab == .today }
    }
}
