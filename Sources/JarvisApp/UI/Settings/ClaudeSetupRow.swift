import JarvisKit
import SwiftUI

/// A command-line brain Jarvis can install and sign in to: Claude Code or Codex.
@MainActor
struct AgentSetup {
    let name: String
    let plan: String
    let status: @Sendable () async -> ClaudeCodeSetup.Status
    let install: @Sendable () async throws -> Void
    let openSignIn: @MainActor () throws -> Void

    static let claudeCode = AgentSetup(
        name: "Claude Code",
        plan: "Uses your Claude Pro or Max plan. Free Claude accounts can't use Claude Code; pick the API key option instead.",
        status: ClaudeCodeSetup.status, install: ClaudeCodeSetup.install, openSignIn: ClaudeCodeSetup.openSignIn)
    static let codex = AgentSetup(
        name: "Codex",
        plan: "Uses your ChatGPT plan (Plus, Pro, Business or Edu). Signing in opens your browser once.",
        status: CodexSetup.status, install: CodexSetup.install, openSignIn: CodexSetup.openSignIn)
}

/// Install and sign in to Claude Code or Codex without leaving Jarvis (sign-in opens one Terminal window).
struct ClaudeSetupRow: View {
    var agent = AgentSetup.claudeCode
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
                    Button("Install \(agent.name)", action: install)
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
            Text(agent.name)
            Text(detail)
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.orange)
        }
        Text(agent.plan)
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
                try await agent.install()
            } catch {
                self.error = error.localizedDescription
            }
            installing = false
            status = await agent.status()
        }
    }

    private func signIn() {
        error = nil
        do {
            try agent.openSignIn()
            waitingForSignIn = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Checks once, then every few seconds while a sign-in is in progress (up to 10 minutes).
    private func watch() async {
        status = await agent.status()
        guard waitingForSignIn else { return }
        for _ in 0..<200 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            status = await agent.status()
            if case .ready = status { break }
        }
        waitingForSignIn = false
    }
}
