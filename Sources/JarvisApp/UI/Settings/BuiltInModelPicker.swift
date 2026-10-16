import JarvisKit
import SwiftUI

/// Choose, download and remove the model Jarvis runs itself.
struct BuiltInModelPicker: View {
    let state: AppState
    let downloader: ModelDownloader

    private var model: LocalModel {
        LocalModels.model(id: state.settings.builtInModelID) ?? LocalModels.recommended()
    }

    private var memoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory >> 30) }

    var body: some View {
        Picker("Model", selection: state.binding(\.builtInModelID)) {
            ForEach(LocalModels.offered) { model in
                Text("\(model.name) · \(model.sizeText)").tag(model.id)
            }
        }
        status
        Text(.init(hint))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var status: some View {
        if let download = state.modelDownload {
            if let error = download.error {
                Text(error).foregroundStyle(.orange)
                Button("Try again") { downloader.download(model) }
            } else {
                ProgressView(value: download.fraction) {
                    Text("Downloading \(LocalModels.model(id: download.modelID)?.name ?? "model")…")
                }
                Button("Cancel", action: downloader.cancel)
            }
        } else if LocalModels.isInstalled(model) {
            LabeledContent("Ready") {
                Button("Remove") { downloader.delete(model) }
            }
        } else if model.url == nil {
            Text("Not installed: copy its \(model.fileName) into Jarvis's Models folder.")
                .foregroundStyle(.orange)
        } else {
            Button("Download \(model.name) (\(model.sizeText))") { downloader.download(model) }
        }
    }

    private var hint: String {
        var text = "Runs inside Jarvis: free, private, offline once downloaded. No Ollama needed."
        if model.minMemoryGB > memoryGB {
            text += " This Mac has \(memoryGB) GB of memory, so \(model.name) may be slow; try a smaller one."
        }
        return text
    }
}
