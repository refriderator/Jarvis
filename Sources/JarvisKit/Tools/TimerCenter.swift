import AppKit

/// Runs timers and answers timer commands. When one ends it chimes, shows and says so.
@MainActor
public final class TimerCenter {
    private let state: AppState
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// The chime; replaceable in tests.
    var chime: () -> Void = { NSSound(named: "Glass")?.play() }

    public init(state: AppState) {
        self.state = state
    }

    /// The reply if `text` was a timer command, else nil.
    public func handle(_ text: String, now: Date = .now) -> String? {
        switch TimerCommand.parse(text) {
        case .start(let seconds, let note):
            start(seconds, note: note, now: now)
            return note.map { "Okay, I'll remind you in \(TimerCommand.describe(seconds)) to \($0)." }
                ?? "Timer set for \(TimerCommand.describe(seconds))."
        case .at(let hour, let minute, let pm, let note):
            guard let ends = Self.next(hour: hour, minute: minute, pm: pm, after: now) else { return nil }
            start(max(1, Int(ends.timeIntervalSince(now).rounded())), note: note, alarm: true, now: now)
            let time = ends.formatted(date: .omitted, time: .shortened)
            let day = Calendar.current.isDate(ends, inSameDayAs: now) ? "" : " tomorrow"
            return "Okay, I'll remind you at \(time)\(day)" + (note.map { " to \($0)." } ?? ".")
        case .noAlarms:
            return "I can't set alarms, only timers and reminders. Try \"timer 10 minutes\" or \"remind me at 7 am to get up\"."
        case .cancelAll:
            let count = state.timers.count
            cancelAll()
            return count == 0 ? "There's no timer running." : count == 1 ? "Timer cancelled." : "All \(count) timers cancelled."
        case .status:
            guard !state.timers.isEmpty else { return "There's no timer running." }
            return state.timers.map { "\(TimerCommand.describe(max(0, Int($0.ends.timeIntervalSince(now))))) left on the \($0.label) timer" }
                .joined(separator: "; ") + "."
        case nil:
            return nil
        }
    }

    /// The next time it's `hour`:`minute` (with `pm` nil, whichever of am or pm comes first).
    nonisolated public static func next(hour: Int, minute: Int, pm: Bool?, after now: Date) -> Date? {
        let hours = pm.map { [$0 ? hour % 12 + 12 : hour % 12] } ?? (hour > 12 || hour == 0 ? [hour] : [hour % 12, hour % 12 + 12])
        return hours.compactMap {
            Calendar.current.nextDate(after: now, matching: DateComponents(hour: $0, minute: minute, second: 0),
                                      matchingPolicy: .nextTime)
        }.min()
    }

    public func start(_ seconds: Int, note: String? = nil, alarm: Bool = false, now: Date = .now) {
        let timer = JarvisTimer(seconds: seconds, ends: now.addingTimeInterval(TimeInterval(seconds)), note: note, alarm: alarm)
        state.setTimers((state.timers + [timer]).sorted { $0.ends < $1.ends })
        tasks[timer.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.fire(timer)
        }
    }

    public func cancel(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        state.setTimers(state.timers.filter { $0.id != id })
    }

    public func cancelAll() {
        state.timers.forEach { cancel($0.id) }
    }

    private func fire(_ timer: JarvisTimer) {
        tasks[timer.id] = nil
        state.setTimers(state.timers.filter { $0.id != timer.id })
        chime()
        state.send(.summon)
        let text = timer.note.map { "Reminder: \($0)." } ?? "Your \(timer.label) timer is done."
        state.announce(text, source: "Timer", spoken: true)
    }
}
