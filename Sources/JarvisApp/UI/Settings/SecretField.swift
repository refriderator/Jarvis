import JarvisKit
import SwiftUI

/// A key or token field that saves straight to the Keychain. The saved value is
/// never shown again; the field only says whether one is stored.
struct SecretField: View {
    let state: AppState
    let key: SecretKey
    let label: String
    @State private var draft = ""
    @State private var isStored = false

    var body: some View {
        LabeledContent(label) {
            HStack {
                SecureField(isStored ? "Saved in Keychain" : "Paste here", text: $draft)
                    .onSubmit(save)
                if !draft.isEmpty {
                    Button("Save", action: save)
                } else if isStored {
                    Button("Remove") {
                        state.setSecret(key, nil)
                        isStored = false
                    }
                }
            }
        }
        .onAppear { isStored = state.secret(key) != nil }
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state.setSecret(key, value)
        draft = ""
        isStored = true
    }
}
