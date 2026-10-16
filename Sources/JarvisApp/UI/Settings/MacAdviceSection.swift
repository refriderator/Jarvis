import AppKit
import JarvisKit
import SwiftUI

/// "This Mac": what it can run, the suggested brains, and anything to watch out for.
struct MacAdviceSection: View {
    let state: AppState
    let downloader: ModelDownloader
    @State private var mac: MacProfile?

    var body: some View {
        Section("This Mac") {
            if let mac {
                let advice = MacAdvice.for(mac)
                LabeledContent(mac.name) {
                    Text("\(mac.chip) · \(mac.memoryGB) GB")
                        .foregroundStyle(.secondary)
                }
                LabeledContent {
                    if isApplied(advice) {
                        Label("In use", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Use this") { apply(advice) }
                    }
                } label: {
                    Text("Suggested")
                    Text(advice.summary)
                }
                ForEach(advice.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear {
            mac = MacProfile.current(hasNotch: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })
        }
    }

    private func isApplied(_ advice: MacAdvice) -> Bool {
        let settings = state.settings
        return settings.localBrain == advice.localBrain && settings.cloudBrain == .claudeCode
            && (advice.model.map { $0.id == settings.builtInModelID } ?? true)
    }

    private func apply(_ advice: MacAdvice) {
        state.update {
            $0.localBrain = advice.localBrain
            $0.cloudBrain = .claudeCode
            if let model = advice.model { $0.builtInModelID = model.id }
        }
        if let model = advice.model, !LocalModels.isInstalled(model) {
            downloader.download(model)
        }
    }
}
