import CoreGraphics
import Foundation
import Observation

/// The one source of truth. Views read it; changes go through its methods.
@MainActor
@Observable
public final class AppState {
    public private(set) var notch: NotchStateMachine
    public private(set) var layout: NotchLayout
    public private(set) var settings: Settings
    public private(set) var nowPlaying: NowPlaying?
    public private(set) var weather: WeatherReport?
    public private(set) var turns: [Turn] = []
    public private(set) var tokens: TokenMeter
    public private(set) var voice: VoiceStatus = .idle
    /// The caption window is up: "TODAY" is hidden and the live words or the answer show under the music.
    /// It starts with a question, a voice prompt or a timer, and ends when it's been read (or on dismiss).
    public private(set) var captionActive = false
    /// The user clicked the caption to keep it on screen, in full, until they click off.
    public private(set) var captionPinned = false
    public private(set) var timers: [JarvisTimer] = []
    /// Today's calendar events for the open notch; empty without Calendar access.
    public private(set) var agenda: [AgendaItem] = []
    /// What's due from Notion for the open notch; empty when off or not connected.
    public private(set) var due: [DueItem] = []
    /// The built-in model being downloaded, if any.
    public private(set) var modelDownload: ModelDownload?
    /// What's typed in the input bar; kept here so it survives the panel closing.
    public private(set) var draft = ""
    /// A window held in the notch, if any.
    public private(set) var dock = NotchDock()
    /// A browser's Picture in Picture video held by the notch.
    public private(set) var video = VideoDock()
    /// The last minute of system readings, for the Monitor tab (filled only while it shows).
    public private(set) var stats = StatsHistory()

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let secrets: SecretStore
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let usage: UsageStore
    @ObservationIgnored public let permissions: PermissionChecking

    public var skin: Skin { SkinCatalog.skin(id: settings.skinID) }

    public init(store: SettingsStore = MemorySettingsStore(),
                secrets: SecretStore = MemorySecretStore(),
                loginItem: LoginItem = NoLoginItem(),
                usage: UsageStore = MemoryUsageStore(),
                permissions: PermissionChecking = SystemPermissions(),
                layout: NotchLayout = NotchLayout(notch: .zero)) {
        let settings = store.load()
        self.settings = settings
        self.notch = NotchStateMachine(trigger: settings.openTrigger)
        self.store = store
        self.secrets = secrets
        self.loginItem = loginItem
        self.usage = usage
        self.tokens = usage.load()
        self.permissions = permissions
        self.layout = layout
    }

    // MARK: Notch

    public func send(_ event: NotchEvent) {
        notch.holdOpen = captionActive
        notch.handle(event)
    }

    public func updateLayout(_ layout: NotchLayout) {
        self.layout = layout
        syncCaption()
        self.layout.agendaRows = todayRows
        self.layout.timerRows = min(timers.count, NotchLayout.maxTimerRows)
        syncDock()
    }

    // MARK: Held window

    public func updateDock(_ change: (inout NotchDock) -> Void) {
        change(&dock)
        syncDock()
    }

    public func updateVideo(_ change: (inout VideoDock) -> Void) {
        let wasHeld = video.held
        change(&video)
        // A newly held video folds the tab's content away; letting go of it brings the content back.
        if video.held != wasHeld { dock.contentHidden = video.held }
        syncDock()
    }

    public func addStats(_ sample: StatsSample) {
        stats.add(sample)
    }

    private func syncDock() {
        layout.showsShelf = dock.showsShelf
        layout.browserLarge = dock.tab == .browser && dock.browserLarge && dock.dragging == nil
        layout.browserMini = dock.browserFullscreen && !video.held && dock.dragging == nil
        layout.videoAspect = video.held && !video.tucked || video.catching ? video.aspect : nil
        layout.tuckedVideo = video.held && video.tucked ? video.tuckedSize : nil
        layout.offersVideo = video.available || video.held
        layout.videoMinimum = video.minimum
        layout.hidesContent = (video.catching || dock.contentHidden) && dock.dragging == nil
        // The tab beside the closed notch: held apps, and a video button while a loose video floats.
        layout.tabSlots = dock.tabSlots + (video.available && !video.held || video.held && video.tucked ? 1 : 0)
        // Keep holds the dropdown open, whatever the tab.
        notch.locked = dock.keep != .off
        layout.theater = video.held && video.theater
        layout.tallForTheater = video.held && video.tallForTheater
        // Nothing can be clicked mid-drag, so a dragged window (or file) opens it on hover.
        notch.openOnHover = dock.dragging != nil || dock.tab == .finder
    }

    // MARK: Widgets

    public func setNowPlaying(_ nowPlaying: NowPlaying?) {
        self.nowPlaying = nowPlaying
    }

    public func setWeather(_ weather: WeatherReport?) {
        self.weather = weather
    }

    // MARK: Conversation

    public func setDraft(_ text: String) {
        draft = text
    }

    public func beginTurn(_ question: String, spoken: Bool = false) {
        turns.append(Turn(question: question, spoken: spoken))
        // Only the last few turns are ever shown or sent back.
        if turns.count > 20 { turns.removeFirst(turns.count - 20) }
        draft = ""
        startCaption()
    }

    /// Pauses the last turn until the user says whether to use the cloud brain.
    public func setAwaitingCloud(_ waiting: Bool, source: String? = nil) {
        guard let last = turns.indices.last else { return }
        turns[last].awaitingCloud = waiting
        turns[last].source = source
    }

    public func finishTurn(_ answer: String, source: String, tokens count: Int) {
        guard let last = turns.indices.last else { return }
        turns[last].awaitingCloud = false
        turns[last].answeredAt = .now
        turns[last].answer = Readable.clean(answer)
        turns[last].source = source
        turns[last].tokens = count
        syncCaption()
        if count > 0 {
            tokens.add(count)
            usage.save(tokens)
        }
    }

    public func failTurn(_ message: String) {
        guard let last = turns.indices.last else { return }
        turns[last].answer = message
        turns[last].answeredAt = .now
        turns[last].failed = true
        turns[last].awaitingCloud = false
        syncCaption()
    }

    /// A message from Jarvis itself (a timer going off, a voice problem), shown like an answer.
    public func announce(_ text: String, source: String, failed: Bool = false, spoken: Bool = false) {
        var turn = Turn(question: "", spoken: spoken)
        turn.answer = text
        turn.answeredAt = .now
        turn.source = source
        turn.failed = failed
        turns.append(turn)
        if turns.count > 20 { turns.removeFirst(turns.count - 20) }
        startCaption()
    }

    // MARK: Caption

    private func startCaption() {
        captionActive = true
        syncCaption()
    }

    /// The caption is over: back to the "TODAY" list.
    public func endCaption() {
        guard captionActive || captionPinned else { return }
        captionActive = false
        captionPinned = false
        syncCaption()
    }

    /// How long the "last response" tab stays after an answer.
    public static let lastResponseWindow: TimeInterval = 60

    /// The latest answer if it came in the last minute and isn't already on screen as the caption.
    public func lastResponse(now: Date = .now) -> Turn? {
        guard !captionActive, let turn = turns.last, turn.answer != nil, !turn.failed || !turn.question.isEmpty,
              let answered = turn.answeredAt, now.timeIntervalSince(answered) < Self.lastResponseWindow else { return nil }
        return turn
    }

    /// The "last response" tab: show that answer as a kept caption, silently.
    public func showLastResponse() {
        guard lastResponse() != nil else { return }
        captionActive = true
        captionPinned = true
        syncCaption()
    }

    /// Click the caption to keep it (and click again to let it go).
    public func toggleCaptionPin() {
        guard captionActive else { return }
        captionPinned.toggle()
        syncCaption()
    }

    /// Nothing left to wait for: not listening, not speaking, and the last turn has its answer.
    public var captionFinished: Bool {
        guard captionActive, !voice.isListening, voice != .speaking, let turn = turns.last else { return false }
        return turn.answer != nil && !turn.awaitingCloud
    }

    /// How long a finished caption stays so it can be read: a short beat after speech, longer for text only.
    public var captionLinger: TimeInterval {
        guard let turn = turns.last else { return 2 }
        return turn.spoken ? 2 : min(3 + Double(turn.answer?.count ?? 0) * 0.05, 15)
    }

    private func syncCaption() {
        layout.showsCaption = captionActive
        layout.captionHeight = captionPinned
            ? NotchLayout.captionHeight(forAnswerLength: turns.last?.answer?.count ?? 0)
            : NotchLayout.defaultCaptionHeight
    }

    public func resetTokens() {
        tokens.reset()
        usage.save(tokens)
    }

    // MARK: Voice, timers, calendar

    public func setVoice(_ voice: VoiceStatus) {
        self.voice = voice
        if voice.isListening { startCaption() }
    }

    public func setTimers(_ timers: [JarvisTimer]) {
        self.timers = timers
        layout.timerRows = min(timers.count, NotchLayout.maxTimerRows)
    }

    public func setAgenda(_ agenda: [AgendaItem]) {
        self.agenda = agenda
        layout.agendaRows = todayRows
    }

    public func setDue(_ due: [DueItem]) {
        self.due = due
        layout.agendaRows = todayRows
    }

    /// Rows the "TODAY" list needs; 0 when it's turned off in Settings.
    private var todayRows: Int {
        min(agenda.count + due.count, NotchLayout.maxAgendaRows)
    }

    // MARK: Built-in model

    public func setModelDownload(_ download: ModelDownload?) {
        modelDownload = download
    }

    // MARK: Settings

    /// Changes settings, applies side effects, and saves.
    public func update(_ change: (inout Settings) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        if new.launchAtLogin != settings.launchAtLogin {
            new.launchAtLogin = loginItem.setEnabled(new.launchAtLogin)
        }
        settings = new
        notch.trigger = new.openTrigger
        layout.agendaRows = todayRows
        store.save(new)
    }

    public func selectSkin(id: String) {
        update { $0.skinID = id }
    }

    // MARK: Secrets

    public func secret(_ key: SecretKey) -> String? {
        secrets.get(key)
    }

    public func setSecret(_ key: SecretKey, _ value: String?) {
        secrets.set(key, value)
    }
}
