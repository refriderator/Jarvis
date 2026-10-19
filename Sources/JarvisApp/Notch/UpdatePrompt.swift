import AppKit
import JarvisKit

/// Asks under the notch when a newer release of Jarvis is out ("Jarvis 1.3 is out · Update · Later"): a little
/// after launch, then once a day while it runs. Update runs Settings' updater; Later waits for the next launch.
@MainActor
final class UpdatePrompt {
    private let state: AppState
    private let notice: NoticePanel
    private var daily: Timer?
    /// Later (or Update) was clicked: not again until Jarvis next opens.
    private var answered = false
    /// The release the notice is asking about now, so the daily check doesn't ask twice.
    private var asking: AppVersion?

    init(state: AppState, notice: NoticePanel) {
        self.state = state
        self.notice = notice
        // Not in the first moments: launching (and the welcome) comes first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check() }
        daily = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard !answered, state.settings.checkForUpdates, state.settings.hasCompletedWelcome else { return }
        Task { [weak self] in
            guard let release = await Updater.newerRelease(), let self, !answered, asking != release.version else { return }
            asking = release.version
            notice.ask("Jarvis \(release.version) is out", choices: [
                ("Update", { [weak self] in self?.update(release) }),
                ("Later", { [weak self] in self?.answered = true }),
            ])
        }
    }

    /// The same as Settings › General › Update; without the folder it was built from, the release's page instead.
    private func update(_ release: Release) {
        answered = true
        do { try Updater.openUpdate() } catch { NSWorkspace.shared.open(release.page) }
    }
}
