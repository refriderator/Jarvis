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
        case .start(let seconds):
            start(seconds, now: now)
            return "Timer set for \(TimerCommand.describe(seconds))."
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
