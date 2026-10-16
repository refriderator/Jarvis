import JarvisKit
import SwiftUI

struct UsageTab: View {
    let state: AppState

    var body: some View {
        Form {
            Toggle("Show token counts", isOn: state.binding(\.showTokens))
            LabeledContent("Last reply", value: state.tokens.lastReply.formatted())
            LabeledContent("This session", value: state.tokens.session.formatted())
            LabeledContent("Today", value: state.tokens.today.formatted())
            Button("Reset counts") { state.resetTokens() }
            Text("Tokens only, never money. Answers from Apple's on-device model don't report tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
