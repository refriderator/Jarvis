import JarvisKit
import SwiftUI

/// Picks one of the models pulled into Ollama (Qwen, Gemma, ...).
/// Falls back to a text field when Ollama isn't running.
struct OllamaModelPicker: View {
    let state: AppState
    @State private var installed: [String] = []

    var body: some View {
        Group {
            if installed.isEmpty {
                TextField("Ollama model", text: state.binding(\.ollamaModel))
            } else {
                Picker("Ollama model", selection: state.binding(\.ollamaModel)) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .task { installed = await OllamaModels.installed() }
    }

    /// Installed models, plus the saved one so the picker never shows a blank.
    private var choices: [String] {
        installed.contains(state.settings.ollamaModel) ? installed : [state.settings.ollamaModel] + installed
    }
}
