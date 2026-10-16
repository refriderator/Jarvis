import AppKit
import JarvisKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(store: FileSettingsStore(), secrets: KeychainStore(), loginItem: SystemLoginItem(),
                         usage: FileUsageStore())
    private let engine = LlamaEngine()
    private let calendar = EventKitCalendar()
    private let hotkeys = Hotkeys()
    lazy var timers = TimerCenter(state: state)
    /// Set once launched; the menu reads it.
    private(set) var voice: VoiceSession?
    private lazy var downloader = ModelDownloader(state: state)
    private var notch: NotchController?
    private var relay: ToolRelay.Server?
    private let settingsWindow = WindowPresenter()
    private let welcomeWindow = WindowPresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, notch and menu keep working.
        NSApp.setActivationPolicy(.accessory)
        let music = MusicAppsPlayer()
        let weather = OpenMeteoWeather(locator: CurrentLocation())
        let feed = WidgetFeed(state: state, player: music, weather: weather, calendar: calendar,
                              notion: { [state] in state.secret(.notionToken).map { NotionAPI(token: $0) } })
        feed.start()
        let state = state
        let launcher = AppLauncher(player: music)
        let mac = MacControls()
        mac.openApp = { name in
            guard let opened = launcher.open(name) else { throw ChatError("No app called \(name) is installed.") }
            return "Opened \(opened)."
        }
        let tools = Toolbox(timers: timers, calendar: calendar, camera: MacCamera(), apps: launcher, mac: mac, weather: weather,
                            notion: { state.secret(.notionToken).map { NotionTools(token: $0) } })
        let assistant = Assistant(state: state, makeLocal: { Brains.local($0, engine: self.engine) },
                                  makeCloud: { Brains.cloud($0, secret: state.secret) }, tools: tools,
                                  log: TurnLog { state.settings.logConversations })
        let voice = VoiceSession(state: state, assistant: assistant, listener: SpeechListener(),
                                 speaker: SystemSpeaker(), hotkeys: hotkeys)
        voice.start()
        self.voice = voice
        notch = NotchController(state: state, feed: feed, assistant: assistant, voice: voice, openSettings: { [weak self] in
            self?.state.send(.dismiss)
            self?.showSettings()
        }, cancelTimer: { [weak self] in self?.timers.cancel($0) })
        notch?.connect(mac)
        // Claude Code's calls to the Mac tools arrive here, while Claude's access allows them.
        let relay = ToolRelay.Server(kit: { tools.cloudMacKit() ?? CombinedKit([]) },
                                     allowed: { state.settings.claudeAccess != .none })
        try? relay.start()
        self.relay = relay
        if !state.settings.hasCompletedWelcome {
            showWelcome()
        }
    }

    /// Frees the local model before quitting; ggml's GPU teardown aborts if it is still loaded.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notch?.releaseWindows()
        Task {
            await engine.unload()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Launching Jarvis again while it runs opens Settings, so it stays
    /// reachable with the menu icon hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        settingsWindow.show(title: "Jarvis Settings") { SettingsView(state: self.state, downloader: self.downloader) }
    }

    func showWelcome() {
        welcomeWindow.show(title: "Welcome to Jarvis") {
            WelcomeView(state: self.state, downloader: self.downloader) { [weak self] in self?.welcomeWindow.close() }
        }
    }
}
