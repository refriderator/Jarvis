import Foundation

/// Several tool kits as one, each tool named "<kit>_<tool>" ("mac_open_app", "timer_start"): what the cloud brain gets
/// for this Mac when Settings › Connections › Claude's access allows it.
public struct CombinedKit: ToolKit {
    public let name = "jarvis"
    public var mcpFlag: String? { ToolRelay.flag }
    let kits: [ToolKit]

    public init(_ kits: [ToolKit]) {
        self.kits = kits
    }

    public var instructions: String {
        "You can do things on the user's Mac with Jarvis's tools: " + kits.map(\.instructions).joined(separator: " ")
    }

    public var definitions: [ToolDefinition] {
        kits.flatMap { kit in
            kit.definitions.map { ToolDefinition(name: "\(kit.name)_\($0.name)", description: $0.description, schema: $0.schema) }
        }
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        guard let kit = kits.first(where: { name.hasPrefix($0.name + "_") }) else { throw ChatError("No tool named \(name).") }
        return try await kit.call(String(name.dropFirst(kit.name.count + 1)), arguments: arguments)
    }
}

/// How Claude Code reaches the running app's tools. Claude Code starts `Jarvis --tools-mcp` as an MCP server; that
/// separate process can't touch the notch or the timers, so it passes each call over a socket in Application Support
/// (only this user can open it) to the app, which runs it. One JSON line each way per connection.
public enum ToolRelay {
    public static let flag = "--tools-mcp"

    public static var socketURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Jarvis/tools.sock")
    }

    /// The app's side: answers "list" and "call" requests with `kit`, while `allowed` says Claude may.
    public final class Server: @unchecked Sendable {
        private let path: String
        private let handle: @Sendable ([String: Any]) async -> [String: Any]
        private var listener: Int32 = -1

        public init(kit: @escaping @MainActor () -> ToolKit, allowed: @escaping @MainActor () -> Bool,
                    path: URL = ToolRelay.socketURL) {
            self.path = path.path
            handle = { request in
                await MainActor.run { allowed() } ? await Self.answer(request, kit: await MainActor.run { kit() })
                    : ["error": "Claude's access to this Mac is off (Jarvis Settings › Connections)."]
            }
        }

        deinit { stop() }

        public func start() throws {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            unlink(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw ChatError("Couldn't open the tools socket.") }
            var address = try ToolRelay.address(path)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
                close(fd)
                throw ChatError("Couldn't listen on the tools socket.")
            }
            listener = fd
            Thread.detachNewThread { [weak self] in
                while let self, self.listener >= 0 {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { break }
                    Thread.detachNewThread { self.serve(client) }
                }
            }
        }

        public func stop() {
            guard listener >= 0 else { return }
            close(listener)
            listener = -1
            unlink(path)
        }

        private func serve(_ client: Int32) {
            let request = ToolRelay.readAll(client).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            let handle = handle
            Task.detached {
                let reply = await handle(request)
                ToolRelay.write(reply, to: client)
                close(client)
            }
        }

        private static func answer(_ request: [String: Any], kit: ToolKit) async -> [String: Any] {
            switch request["op"] as? String {
            case "list":
                return ["instructions": kit.instructions,
                        "tools": kit.definitions.map { ["name": $0.name, "description": $0.description, "schema": $0.schema] }]
            case "call":
                let arguments = (try? JSONSerialization.data(withJSONObject: request["arguments"] ?? [:])) ?? Data("{}".utf8)
                do {
                    return ["text": try await kit.call(request["name"] as? String ?? "", arguments: arguments)]
                } catch {
                    return ["error": error.localizedDescription]
                }
            default:
                return ["error": "Unknown request."]
            }
        }
    }

    /// The MCP process's side: the app's tools, reached over the socket.
    public struct Client: ToolKit {
        public let name = "jarvis"
        public var mcpFlag: String? { ToolRelay.flag }
        public let instructions: String
        public let definitions: [ToolDefinition]
        private let path: String

        /// Asks the app for its tools; throws when Jarvis isn't running or Claude's access is off.
        public init(path: URL = ToolRelay.socketURL) throws {
            self.path = path.path
            let reply = try ToolRelay.send(["op": "list"], path: path.path)
            if let error = reply["error"] as? String { throw ChatError(error) }
            instructions = reply["instructions"] as? String ?? ""
            definitions = (reply["tools"] as? [[String: String]] ?? []).compactMap { tool in
                guard let name = tool["name"], let description = tool["description"], let schema = tool["schema"] else { return nil }
                return ToolDefinition(name: name, description: description, schema: schema)
            }
        }

        public func call(_ name: String, arguments: Data) async throws -> String {
            let path = path
            // Only Sendable values cross into the detached task; the dictionaries stay inside it.
            let (text, error) = try await Task.detached { () throws -> (String?, String?) in
                let input = (try? JSONSerialization.jsonObject(with: arguments)) ?? [:]
                let reply = try ToolRelay.send(["op": "call", "name": name, "arguments": input], path: path)
                return (reply["text"] as? String, reply["error"] as? String)
            }.value
            if let error { throw ChatError(error) }
            return text ?? ""
        }
    }

    // MARK: Socket plumbing

    static func send(_ request: [String: Any], path: String) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ChatError("Couldn't reach Jarvis.") }
        defer { close(fd) }
        var address = try address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw ChatError("Jarvis isn't running, so its tools can't be used.") }
        write(request, to: fd)
        shutdown(fd, SHUT_WR)
        guard let data = readAll(fd), let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ChatError("Jarvis didn't answer.")
        }
        return reply
    }

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ChatError("The socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return address
    }

    /// Reads until the other side stops writing (it shuts down or closes).
    static func readAll(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(buffer, count: count)
        }
    }

    static func write(_ object: [String: Any], to fd: Int32) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = Foundation.write(fd, raw.baseAddress! + sent, raw.count - sent)
                if count <= 0 { return }
                sent += count
            }
        }
    }
}
