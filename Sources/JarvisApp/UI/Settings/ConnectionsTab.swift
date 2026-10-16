import JarvisKit
import SwiftUI

/// Who answers, keys and services. Also used by the welcome flow.
struct ConnectionsTab: View {
    let state: AppState
    let downloader: ModelDownloader
    /// The welcome's version: just the brains. Training and services (Notion, calendars) wait for Settings.
    var compact = false

    var body: some View {
        Form {
            MacAdviceSection(state: state, downloader: downloader)
            Section {
                Picker("Local brain", selection: state.binding(\.localBrain)) {
                    Text("Apple on-device").tag(LocalBrain.apple)
                    Text("Built-in model (Qwen)").tag(LocalBrain.builtIn)
                    Text("Ollama").tag(LocalBrain.ollama)
                    Text("Off").tag(LocalBrain.off)
                }
                switch state.settings.localBrain {
                case .apple:
                    note(AppleOnDeviceProvider.isAvailable
                         ? "Built into macOS: free, private, works offline."
                         : "Apple's on-device model needs macOS 26 with Apple Intelligence turned on, so questions go to the "
                           + "cloud brain. Or pick the built-in model.")
                case .builtIn:
                    BuiltInModelPicker(state: state, downloader: downloader)
                case .ollama:
                    OllamaModelPicker(state: state)
                    note("Uses Ollama at \(Brains.ollamaURL). Pull a model first, e.g. `ollama pull qwen3:8b`.")
                case .off:
                    note("Every question goes to the cloud brain.")
                }
                if state.settings.localBrain != .off {
                    Toggle("Local brain first", isOn: state.binding(\.localFirst))
                    note(state.settings.localFirst
                         ? "It tries everything (writing, maths, code, timers, calendar, Notion) and hands off to the cloud "
                           + "only when unsure, or for news and the camera. Apple on-device can't use Notion."
                         : "Only small questions stay on this Mac; writing, code, maths and Notion go to the cloud.")
                }
            } header: {
                Text("Small questions")
            }
            Section {
                Picker("Cloud brain", selection: state.binding(\.cloudBrain)) {
                    Text("Claude Code (your subscription)").tag(CloudBrain.claudeCode)
                    Text("Claude API key").tag(CloudBrain.claude)
                    Text("OpenAI-compatible").tag(CloudBrain.openAICompatible)
                }
                switch state.settings.cloudBrain {
                case .claudeCode:
                    ClaudeSetupRow()
                    TextField("Model", text: state.binding(\.claudeModel))
                case .claude:
                    SecretField(state: state, key: .claudeAPIKey, label: "API key")
                    TextField("Model", text: state.binding(\.claudeModel))
                    note("Billed per use by Anthropic, separately from a Claude subscription.")
                case .openAICompatible:
                    TextField("Base URL", text: state.binding(\.compatibleBaseURL))
                    TextField("Model", text: state.binding(\.compatibleModel))
                    SecretField(state: state, key: .compatibleAPIKey, label: "API key (optional)")
                }
                Toggle("Token saving", isOn: state.binding(\.askBeforeCloud))
                note("Asks before a question goes to the cloud brain, so tokens are only used when you say so. "
                     + "Questions starting with \"Claude,\" skip the check.")
            } header: {
                Text("Big questions and Notion")
            } footer: {
                note("Start a question with \"Claude,\" to send it straight to the cloud brain.")
            }
            if !compact {
            Section {
                Toggle("Log conversations", isOn: state.binding(\.logConversations))
                note("Saves every question, the exact prompts sent to each brain and their raw replies, one file a day, "
                     + "to see what Jarvis did or to improve a local model. Stays on this Mac.")
                Button("Show Logs in Finder") {
                    try? FileManager.default.createDirectory(at: TurnLog.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(TurnLog.folder)
                }
            } header: {
                Text("Training")
            }
            Section("Services") {
                SecretField(state: state, key: .notionToken, label: "Notion token")
                note("Make an integration at notion.so/my-integrations, paste its token here, then in Notion open each page "
                     + "Jarvis may use › ••• › Connections › add it. Notion requests go to Claude Code or the Claude API.")
                PermissionRow(state: state, permission: .calendar)
                CalendarAccountsRow()
            }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(.init(text))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
