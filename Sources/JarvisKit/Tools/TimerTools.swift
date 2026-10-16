import Foundation

/// Timers and reminders as tools for the local brain. Values are checked here, not trusted.
public struct TimerTools: ToolKit {
    public let name = "timer"
    public static let maxSeconds = 24 * 3600
    private let center: TimerCenter

    public init(center: TimerCenter) {
        self.center = center
    }

    public var instructions: String { "Set, list and cancel timers and reminders." }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "start", description: "Start a timer or reminder, either after some seconds or at a clock time today/tomorrow. Add a short note for reminders.",
                           schema: #"{"type":"object","properties":{"seconds":{"type":"integer"},"at":{"type":"string","description":"24-hour HH:MM"},"note":{"type":"string"}}}"#),
            ToolDefinition(name: "list", description: "List running timers.", schema: #"{"type":"object","properties":{}}"#),
            ToolDefinition(name: "cancel", description: "Cancel all running timers.", schema: #"{"type":"object","properties":{}}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        return try await MainActor.run {
            switch name {
            case "start":
                let seconds = try Self.seconds(input, now: .now)
                let note = (input["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                center.start(seconds, note: note, alarm: (input["at"] as? String).map { !$0.isEmpty } ?? false)
                return "Timer set for \(TimerCommand.describe(seconds))" + (note.map { " (\($0))" } ?? "") + "."
            case "list":
                return center.handle("how long is left on my timer") ?? "No timers."
            case "cancel":
                return center.handle("cancel the timer") ?? "No timers."
            default:
                throw ChatError("No tool named \(name).")
            }
        }
    }

    /// Seconds from `seconds`, or until the next `at` (today, else tomorrow). Refuses anything over a day.
    static func seconds(_ input: [String: Any], now: Date) throws -> Int {
        if let at = input["at"] as? String, !at.isEmpty {
            let parts = at.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]),
                  let next = Calendar.current.nextDate(after: now, matching: DateComponents(hour: parts[0], minute: parts[1]),
                                                       matchingPolicy: .nextTime) else {
                throw ChatError("\"at\" must be a 24-hour time like 17:30.")
            }
            return max(1, Int(next.timeIntervalSince(now).rounded()))
        }
        let seconds = (input["seconds"] as? NSNumber)?.intValue ?? 0
        guard (1...maxSeconds).contains(seconds) else { throw ChatError("seconds must be between 1 and \(maxSeconds).") }
        return seconds
    }
}
