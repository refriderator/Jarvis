import JarvisKit
import SwiftUI

/// Voice and microphone choices. Also used by the welcome flow.
struct VoiceTab: View {
    let state: AppState
    @State private var voices: [VoiceOption] = []
    @State private var microphones: [MicrophoneOption] = []

    var body: some View {
        Form {
            Picker("Voice", selection: state.binding(\.voiceID)) {
                Text("System voice").tag(String?.none)
                ForEach(voices) { voice in
                    Text(voiceLabel(voice)).tag(Optional(voice.id))
                }
            }
            Button("Use my Personal Voice…") {
                Task {
                    _ = await VoiceCatalog.requestPersonalVoice()
                    voices = VoiceCatalog.installed()
                }
            }
            LabeledContent("Speed") {
                Slider(value: state.binding(\.speechRate), in: 0.3...0.7)
            }
            Picker("Microphone", selection: state.binding(\.micDeviceID)) {
                Text("System input").tag(String?.none)
                ForEach(microphones) { mic in
                    Text(mic.name).tag(Optional(mic.id))
                }
            }
            Picker("Talk key", selection: state.binding(\.talkMode)) {
                Text("Hold to talk").tag(TalkMode.pushToHold)
                Text("Press to start and stop").tag(TalkMode.toggle)
            }
            Picker("Stop when I pause", selection: state.binding(\.pauseToSend)) {
                Text("Quickly (1 s)").tag(1.0)
                Text("Normal (1.3 s)").tag(1.3)
                Text("Patiently (2 s)").tag(2.0)
                Text("Never: press the key again").tag(0.0)
            }
            Text("Listening ends on its own after this much silence. Holding the talk key ends when you let go.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("More voices: System Settings › Accessibility › Spoken Content › System Voice › Manage Voices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            voices = VoiceCatalog.installed()
            microphones = Microphones.available()
        }
    }

    private func voiceLabel(_ voice: VoiceOption) -> String {
        let quality = voice.quality.isEmpty ? "" : " (\(voice.quality))"
        return "\(voice.name)\(quality) — \(voice.language)"
    }
}
