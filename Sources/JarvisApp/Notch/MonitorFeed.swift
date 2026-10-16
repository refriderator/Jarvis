import AppKit
import JarvisKit

/// Reads the Mac's counters once a second while the Monitor tab is on screen, and not at all otherwise.
@MainActor
final class MonitorFeed {
    private let state: AppState
    private let sampler = SystemStatsSampler()
    private var timer: Timer?

    init(state: AppState) {
        self.state = state
    }

    func start() {
        guard timer == nil else { return }
        _ = sampler.sample()  // baseline
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sample = self.sampler.sample() else { return }
                self.state.addStats(sample)
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
