import AppKit
import Foundation

/// Gets Claude Code installed and signed in from inside Jarvis, so nobody types commands by hand.
public enum ClaudeCodeSetup {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case signedOut
        case ready(account: String?)
    }

    /// Anthropic's own installer; it puts `claude` in ~/.local/bin.
    public static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"

    public static func status() async -> Status {
        guard let claude = ClaudeCodeProvider.find() else { return .notInstalled }
        let output = try? await ProcessRunner.run(claude, arguments: ["auth", "status"],
                                                  environment: ClaudeCodeProvider.environment,
                                                  directory: .temporaryDirectory, input: "", timeout: 20)
        return output.map { parseStatus($0.stdout) } ?? .signedOut
    }

    public static func parseStatus(_ data: Data) -> Status {
        struct Auth: Decodable {
            let loggedIn: Bool?
            let email: String?
        }
        guard let auth = try? JSONDecoder().decode(Auth.self, from: data), auth.loggedIn == true else { return .signedOut }
        return .ready(account: auth.email)
    }

    public static func install() async throws {
        let output = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/bash"), arguments: ["-c", installCommand],
                                                 environment: ClaudeCodeProvider.environment,
                                                 directory: .homeDirectory, input: "", timeout: 600)
        guard output.status == 0, ClaudeCodeProvider.find() != nil else {
            throw ChatError("Installing Claude Code didn't work. Check your connection and try again.")
        }
    }

    /// Signing in needs a browser and a pasted code, so it runs in a Terminal window.
    @MainActor
    public static func openSignIn() throws {
        guard let claude = ClaudeCodeProvider.find() else { throw ChatError("Install Claude Code first.") }
        let quoted = "'" + claude.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let script = """
            #!/bin/sh
            clear
            echo "Signing in to Claude Code for Jarvis. Your browser will open; sign in with your Claude account."
            echo
            \(quoted) auth login
            echo
            echo "All set. You can close this window and go back to Jarvis."
            """
        let url = URL.temporaryDirectory.appending(path: "Sign in to Claude for Jarvis.command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}
