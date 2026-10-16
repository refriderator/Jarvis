import AppKit
import Foundation

/// Gets Codex installed and signed in from inside Jarvis, like `ClaudeCodeSetup`: install with Homebrew (or npm), then
/// sign in with ChatGPT in one Terminal window.
public enum CodexSetup {
    public static func status() async -> ClaudeCodeSetup.Status {
        guard let codex = CodexProvider.find() else { return .notInstalled }
        // `codex login status` exits 0 when signed in, and says how ("Logged in using ChatGPT").
        let output = try? await ProcessRunner.run(codex, arguments: ["login", "status"], environment: CodexProvider.environment,
                                                  directory: .temporaryDirectory, input: "", timeout: 20)
        guard let output, output.status == 0 else { return .signedOut }
        return .ready(account: nil)
    }

    /// Homebrew when it's there, else npm; nil when neither is installed.
    public static var installCommand: String? {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") { return "/opt/homebrew/bin/brew install --cask codex" }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") { return "/usr/local/bin/brew install --cask codex" }
        for npm in ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"] where FileManager.default.isExecutableFile(atPath: npm) {
            return "\(npm) install -g @openai/codex"
        }
        return nil
    }

    public static func install() async throws {
        guard let command = installCommand else {
            throw ChatError("Installing Codex needs Homebrew (brew.sh) or Node.js first.")
        }
        let output = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", command],
                                                 environment: CodexProvider.environment,
                                                 directory: .homeDirectory, input: "", timeout: 600)
        guard output.status == 0, CodexProvider.find() != nil else {
            throw ChatError("Installing Codex didn't work. Check your connection and try again.")
        }
    }

    /// Signing in opens the browser from a Terminal window.
    @MainActor
    public static func openSignIn() throws {
        guard let codex = CodexProvider.find() else { throw ChatError("Install Codex first.") }
        let quoted = "'" + codex.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let script = """
            #!/bin/sh
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            clear
            echo "Signing in to Codex for Jarvis. Your browser will open; sign in with your ChatGPT account."
            echo
            \(quoted) login
            echo
            echo "All set. You can close this window and go back to Jarvis."
            """
        let url = URL.temporaryDirectory.appending(path: "Sign in to Codex for Jarvis.command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}
