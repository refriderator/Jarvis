import Foundation

/// Timers as tools for the local brain (and the cloud one). Reminders and alarms are code (`ReminderCommand`,
/// `AlarmCommand`), never a model's job. The length is
/// given as said and read by `TimerCommand.seconds(in:)`: the model copies words instead of working out seconds.
public struct TimerTools: ToolKit {
    public let name = "timer"
    public static let maxSeconds = 24 * 3600
    private let center: TimerCenter

    public init(center: TimerCenter) {
        self.center = center
    }

    public var instructions: String { "Set, list and cancel timers." }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "start", description: "Start a timer. Give its length in the user's words, like \"10 minutes\" or \"an hour and a half\".",
                           schema: #"{"type":"object","properties":{"duration":{"type":"string"}},"required":["duration"]}"#),
            ToolDefinition(name: "list", description: "List running timers.", schema: #"{"type":"object","properties":{}}"#),
            ToolDefinition(name: "cancel", description: "Cancel all running timers.", schema: #"{"type":"object","properties":{}}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        return try await MainActor.run {
            switch name {
            case "start":
                let seconds = try Self.seconds(input)
                center.start(seconds)
                return "Timer set for \(TimerCommand.describe(seconds))."
            case "list":
                return center.handle("how long is left on my timer") ?? "No timers."
            case "cancel":
                return center.handle("cancel the timer") ?? "No timers."
            default:
                throw ChatError("No tool named \(name).")
            }
        }
    }

    /// Seconds in `duration`. Refuses none, or anything over a day.
    static func seconds(_ input: [String: Any]) throws -> Int {
        let duration = input["duration"] as? String ?? ""
        guard let seconds = TimerCommand.seconds(in: duration), (1...maxSeconds).contains(seconds) else {
            throw ChatError("duration must be a length like \"10 minutes\" or \"an hour and a half\", up to 24 hours.")
        }
        return seconds
    }
}
