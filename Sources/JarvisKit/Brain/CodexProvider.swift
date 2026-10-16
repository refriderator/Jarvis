import Foundation

/// Asks the user's own Codex (`codex exec`), so replies use their ChatGPT plan, set up like `ClaudeCodeProvider`:
/// their own config ignored, no session saved, in an empty folder, read-only unless Claude's access is Full. Web search
/// is on; Notion questions add Jarvis's Notion MCP server, the Mac tools (access Tools or Full) `Jarvis --tools-mcp`,
/// and camera questions attach the photo.
@MainActor
public struct CodexProvider: ChatProvider {
    public let executable: URL
    /// Empty: Codex's own default model.
    public let model: String
    public let jarvisExecutable: URL?
    public var label: String { "Codex" }
    public var supportsExtras: Bool { true }

    public init(executable: URL, model: String, jarvisExecutable: URL? = Bundle.main.executableURL) {
        self.executable = executable
        self.model = model
        self.jarvisExecutable = jarvisExecutable
    }

    /// Where Codex's installers (Homebrew, npm) put it.
    nonisolated public static func find() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/.npm-global/bin/codex"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// HOME for its sign-in, and a PATH with Homebrew's folders (the npm install runs on node).
    nonisolated static var environment: [String: String] {
        let env = ProcessInfo.processInfo.environment
        return ["HOME": env["HOME"] ?? NSHomeDirectory(), "USER": env["USER"] ?? NSUserName(),
                "LOGNAME": env["LOGNAME"] ?? NSUserName(),
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        try await reply(system: system, history: history, extras: .none)
    }

    public func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jarvis-codex")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appending(path: "camera.jpg")
        try? FileManager.default.removeItem(at: photo)
        defer { try? FileManager.default.removeItem(at: photo) }

        var arguments = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config",
                         "--sandbox", extras.computer ? "danger-full-access" : "read-only", "--cd", folder.path,
                         "-c", #"web_search="live""#]
        if !model.isEmpty { arguments += ["-c", "model=\(Self.toml(model))"] }
        var instructions = system
        if let image = extras.image {
            try image.write(to: photo)
            arguments += ["--image", photo.path]
        }
        // MCP servers by -c. The Notion token isn't passed: `Jarvis --notion-mcp` reads it from the Keychain itself,
        // so it never shows up on a command line.
        for kit in [extras.tools, extras.mac].compactMap({ $0 }) {
            guard let flag = kit.mcpFlag, let jarvis = jarvisExecutable else { continue }
            arguments += ["-c", "mcp_servers.\(kit.name)={command=\(Self.toml(jarvis.path)),args=[\(Self.toml(flag))]}"]
            instructions += "\n\n" + kit.instructions
        }
        if extras.computer { instructions += "\n\n" + ClaudeCodeProvider.computerNote }
        arguments.append("-")  // the prompt comes on stdin
        let prompt = "<instructions>\n\(instructions)\n</instructions>\n\n" + history.flattened
        let output = try await ProcessRunner.run(executable, arguments: arguments, environment: Self.environment,
                                                 directory: folder, input: prompt,
                                                 timeout: extras.computer ? 300 : extras.isEmpty ? 120 : 240)
        return try Self.parse(output.stdout)
    }

    /// A TOML string, quoted.
    nonisolated static func toml(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The JSONL events: the last agent message is the answer, usage comes with turn.completed.
    nonisolated public static func parse(_ data: Data) throws -> ChatReply {
        var reply = ChatReply(text: "")
        var failure: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let event = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "item.completed":
                if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
                   let text = item["text"] as? String {
                    reply.text = text
                }
            case "turn.completed":
                let usage = event["usage"] as? [String: Any] ?? [:]
                reply.inputTokens += (usage["input_tokens"] as? Int ?? 0)
                reply.outputTokens += (usage["output_tokens"] as? Int ?? 0)
            case "turn.failed":
                failure = ((event["error"] as? [String: Any])?["message"] as? String) ?? "the turn failed"
            case "error":
                failure = event["message"] as? String ?? failure
            default:
                break
            }
        }
        if reply.text.isEmpty {
            throw ChatError(failure.map { "Codex: \($0)" } ?? "Codex didn't answer. Is it installed and signed in?")
        }
        return reply
    }
}
