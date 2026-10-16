import Foundation

/// Asks the user's own Claude Code (`claude -p`), so replies use their Claude subscription.
/// Runs it stripped down: web search as its only tool, no MCP servers, skills or settings,
/// in an empty folder, which keeps a question near a thousand tokens instead of the full agent context.
/// Notion questions add only Jarvis's own Notion MCP server; camera questions add the Read tool for the photo.
/// Claude's access (Settings) adds Jarvis's Mac tools (Tools), and Claude Code's own commands and file tools (Full).
@MainActor
public struct ClaudeCodeProvider: ChatProvider {
    public let executable: URL
    public let model: String
    /// This app's executable, started as the Notion MCP server (`Jarvis --notion-mcp`).
    public let jarvisExecutable: URL?
    public var label: String { "Claude Code" }
    public var supportsExtras: Bool { true }

    public init(executable: URL, model: String, jarvisExecutable: URL? = Bundle.main.executableURL) {
        self.executable = executable
        self.model = model
        self.jarvisExecutable = jarvisExecutable
    }

    /// Where Claude Code's installers put it.
    nonisolated public static func find() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Claude Code finds its sign-in through HOME and USER; nothing else is passed on.
    nonisolated static var environment: [String: String] {
        let env = ProcessInfo.processInfo.environment
        return ["HOME": env["HOME"] ?? NSHomeDirectory(), "USER": env["USER"] ?? NSUserName(),
                "LOGNAME": env["LOGNAME"] ?? NSUserName(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    public func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        try await reply(system: system, history: history, extras: .none)
    }

    public func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply {
        let folder = FileManager.default.temporaryDirectory.appending(path: "jarvis-claude")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appending(path: "camera.jpg")
        try? FileManager.default.removeItem(at: photo)

        var tools = ["WebSearch"], allowed = ["WebSearch"]
        var environment = Self.environment
        var servers: [String: Any] = [:]
        var prompt = history.flattened
        var fullSystem = system
        if let image = extras.image {
            try image.write(to: photo)
            tools.append("Read")
            allowed.append("Read")
            prompt = "(A photo just taken with the Mac's camera is at ./camera.jpg. Read it to see what the user means.)\n"
                + prompt
        }
        if let kit = extras.tools, let flag = kit.mcpFlag, let jarvis = jarvisExecutable {
            // Secrets ride in Claude Code's environment and the config only names them ("${VAR}"),
            // so the token never shows up on a command line, in a file or in a log.
            let names = Dictionary(uniqueKeysWithValues: kit.environment.keys.map { ($0, "${\($0)}") })
            servers[kit.name] = ["command": jarvis.path, "args": [flag], "env": names]
            environment.merge(kit.environment) { _, secret in secret }
            allowed.append("mcp__\(kit.name)")
            fullSystem += "\n\n" + kit.instructions
        }
        // The Mac tools run in the app; `Jarvis --tools-mcp` passes Claude Code's calls on to it (`ToolRelay`).
        if let kit = extras.mac, let flag = kit.mcpFlag, let jarvis = jarvisExecutable {
            servers[kit.name] = ["command": jarvis.path, "args": [flag]]
            allowed.append("mcp__\(kit.name)")
            fullSystem += "\n\n" + kit.instructions
        }
        var directories: [String] = []
        if extras.computer {
            // Allowed up front: `claude -p` can't stop to ask.
            let own = ["Bash", "Read", "Edit", "Write", "Glob", "Grep"]
            tools += own.filter { !tools.contains($0) }
            allowed += own.filter { !allowed.contains($0) }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            directories = ["--add-dir", home]
            environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
            fullSystem += "\n\n" + Self.computerNote
        }
        let mcp = String(decoding: try JSONSerialization.data(withJSONObject: ["mcpServers": servers]), as: UTF8.self)
        let output = try await ProcessRunner.run(
            executable,
            arguments: ["-p", "--output-format", "json", "--model", model, "--effort", "low",
                        "--system-prompt", fullSystem, "--tools", tools.joined(separator: ","),
                        "--allowedTools", allowed.joined(separator: ","),
                        "--no-session-persistence",
                        "--strict-mcp-config", "--mcp-config", mcp,
                        "--disable-slash-commands", "--exclude-dynamic-system-prompt-sections",
                        "--setting-sources", ""] + directories,
            environment: environment, directory: folder, input: prompt,
            timeout: extras.computer ? 300 : extras.isEmpty ? 120 : 240)
        try? FileManager.default.removeItem(at: photo)
        return try Self.parse(output.stdout)
    }

    /// Said whenever Claude may run commands and edit files: nothing asks first, so it has to be careful itself.
    static let computerNote = """
        You can run shell commands and read and edit files on the user's Mac (their home folder is allowed). Do only \
        what was asked. Never delete, overwrite, move, send or install anything unless the user clearly asked for \
        exactly that; if a request is unclear, say what you would do instead of doing it. Say briefly what you did.
        """

    nonisolated public static func parse(_ data: Data) throws -> ChatReply {
        struct Result: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
                let output_tokens: Int?
            }
            let result: String?
            let is_error: Bool?
            let usage: Usage?
        }
        guard let decoded = try? JSONDecoder().decode(Result.self, from: data) else {
            throw ChatError("Claude Code didn't answer. Is it installed and signed in?")
        }
        let text = decoded.result ?? ""
        if decoded.is_error == true || text.isEmpty {
            throw ChatError(text.isEmpty ? "Claude Code returned nothing." : "Claude Code: \(text)")
        }
        let usage = decoded.usage
        let input = (usage?.input_tokens ?? 0) + (usage?.cache_creation_input_tokens ?? 0)
            + (usage?.cache_read_input_tokens ?? 0)
        return ChatReply(text: text, inputTokens: input, outputTokens: usage?.output_tokens ?? 0)
    }
}
