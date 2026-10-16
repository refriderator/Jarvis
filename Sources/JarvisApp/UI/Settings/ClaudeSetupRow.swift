import JarvisKit
import SwiftUI

/// Install and sign in to Claude Code without leaving Jarvis (sign-in opens one Terminal window).
struct ClaudeSetupRow: View {
    @State private var status: ClaudeCodeSetup.Status?
    @State private var installing = false
    @State private var waitingForSignIn = false
    @State private var error: String?

    var body: some View {
        LabeledContent {
            switch status {
            case nil:
                ProgressView().controlSize(.small)
            case .notInstalled:
                if installing {
                    HStack { ProgressView().controlSize(.small); Text("Installing…") }
                } else {
                    Button("Install Claude Code", action: install)
                }
            case .signedOut:
                if waitingForSignIn {
                    HStack { ProgressView().controlSize(.small); Text("Waiting for sign-in…") }
                } else {
                    Button("Sign in", action: signIn)
                }
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } label: {
            Text("Claude Code")
            Text(detail)
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
        Text("Uses your Claude Pro or Max plan. Free Claude accounts can't use Claude Code; pick the API key option instead.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .task(id: waitingForSignIn) { await watch() }
    }

    private var detail: String {
        switch status {
        case nil: "Checking…"
        case .notInstalled: "Not installed. Jarvis can install it for you."
        case .signedOut: "Installed, not signed in yet."
        case .ready(let account): account.map { "Signed in as \($0)." } ?? "Signed in."
        }
    }

    private func install() {
        installing = true
        error = nil
        Task {
            do {
                try await ClaudeCodeSetup.install()
            } catch {
                self.error = error.localizedDescription
            }
            installing = false
            status = await ClaudeCodeSetup.status()
        }
    }

    private func signIn() {
        error = nil
        do {
            try ClaudeCodeSetup.openSignIn()
            waitingForSignIn = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Checks once, then every few seconds while a sign-in is in progress (up to 10 minutes).
    private func watch() async {
        status = await ClaudeCodeSetup.status()
        guard waitingForSignIn else { return }
        for _ in 0..<200 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            status = await ClaudeCodeSetup.status()
            if case .ready = status { break }
        }
        waitingForSignIn = false
    }
}
