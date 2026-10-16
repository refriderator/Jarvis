import Foundation

/// Raw record of every question and every model call, for training on real use (Settings › Connections ›
/// "Log conversations"). One JSON object per line, a file per day, in Application Support/Jarvis/Logs:
///   {"type": "call", ...}  one model call: the exact system prompt and messages sent, and the raw reply
///                          (tool calls included), so a line is already a training example
///   {"type": "turn", ...}  one question: what was asked, the answer shown, which brain gave it
/// Lines of the same question share `turn`. Nothing leaves this Mac; photos are noted, not saved.
@MainActor
public final class TurnLog {
    public static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Jarvis/Logs", directoryHint: .isDirectory)
    }

    private let isOn: @MainActor () -> Bool
    private let folder: URL
    /// The question being answered; Jarvis answers one at a time.
    private var current: (id: UUID, question: String, spoken: Bool, started: Date)?

    public init(folder: URL = TurnLog.folder, isOn: @escaping @MainActor () -> Bool) {
        self.folder = folder
        self.isOn = isOn
    }

    public func begin(_ question: String, spoken: Bool) {
        current = (UUID(), question, spoken, .now)
    }

    /// The question's outcome: the answer shown, or why there was none.
    public func finish(answer: String?, source: String?, failure: String? = nil) {
        guard let turn = current else { return }
        current = nil
        write(["type": "turn", "turn": turn.id.uuidString, "question": turn.question, "spoken": turn.spoken,
               "answer": answer ?? NSNull(), "source": source ?? NSNull(), "failure": failure ?? NSNull(),
               "seconds": seconds(since: turn.started)])
    }

    /// Wraps a brain so each of its calls is logged under the current question.
    public func recording(_ provider: ChatProvider?) -> ChatProvider? {
        provider.map { RecordedProvider(base: $0, log: self) }
    }

    fileprivate func call(_ brain: String, system: String, history: [ChatMessage], photo: Bool,
                          started: Date, result: Result<ChatReply, Error>) {
        var line: [String: Any] = [
            "type": "call", "turn": current?.id.uuidString ?? NSNull(), "brain": brain,
            "messages": [["role": "system", "content": system]] + history.map { ["role": $0.role.rawValue, "content": $0.text] },
            "photo": photo, "seconds": seconds(since: started),
        ]
        switch result {
        case .success(let reply):
            line["reply"] = reply.text
            line["inputTokens"] = reply.inputTokens
            line["outputTokens"] = reply.outputTokens
        case .failure(let error):
            line["error"] = error.localizedDescription
        }
        write(line)
    }

    private func seconds(since start: Date) -> Double {
        (Date.now.timeIntervalSince(start) * 100).rounded() / 100
    }

    private func write(_ fields: [String: Any]) {
        guard isOn() else { return }
        var fields = fields
        fields["time"] = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current))
        guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return }
        data.append(0x0A)
        let day = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        let file = folder.appending(path: day + ".jsonl")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}

/// A brain that logs each call to a `TurnLog`, otherwise exactly the brain it wraps.
@MainActor
private struct RecordedProvider: ChatProvider {
    let base: ChatProvider
    let log: TurnLog

    var label: String { base.label }
    var supportsExtras: Bool { base.supportsExtras }
    var canUseTools: Bool { base.canUseTools }

    func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        try await record(system: system, history: history, photo: false) {
            try await base.reply(system: system, history: history)
        }
    }

    func reply(system: String, history: [ChatMessage], extras: ChatExtras) async throws -> ChatReply {
        try await record(system: system, history: history, photo: extras.image != nil) {
            try await base.reply(system: system, history: history, extras: extras)
        }
    }

    private func record(system: String, history: [ChatMessage], photo: Bool,
                        _ ask: () async throws -> ChatReply) async throws -> ChatReply {
        let started = Date.now
        do {
            let reply = try await ask()
            log.call(label, system: system, history: history, photo: photo, started: started, result: .success(reply))
            return reply
        } catch {
            log.call(label, system: system, history: history, photo: photo, started: started, result: .failure(error))
            throw error
        }
    }
}
