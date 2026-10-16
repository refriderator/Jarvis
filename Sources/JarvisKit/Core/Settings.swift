import Foundation

/// Every user preference in one value, saved as one JSON file.
/// New toggle = one field here (with a default) + one row in a settings tab.
public struct Settings: Codable, Equatable, Sendable {
    // General
    public var launchAtLogin = false
    public var showInMenuBar = true
    public var openTrigger: OpenTrigger = .click

    /// What the assistant is called (`AssistantName`).
    public var assistantName = AssistantName.standard

    // Voice
    /// `AVSpeechSynthesisVoice.identifier`; nil means the system voice.
    public var voiceID: String?
    /// 0...1, where 0.5 is normal speed.
    public var speechRate = 0.5
    /// `AVCaptureDevice.uniqueID`; nil means the system input.
    public var micDeviceID: String?
    public var talkMode: TalkMode = .pushToHold
    /// Seconds of silence after speech that end listening on their own (0 = only the key or button ends it).
    /// Not used while holding the talk key, where letting go is the signal.
    public var pauseToSend = 1.3
    public var talkHotkey = Hotkey.talk
    public var typeHotkey = Hotkey.type

    // Appearance
    public var skinID = SkinCatalog.fallback.id
    public var captionSize: CaptionSize = .regular
    /// City for the notch's weather; empty means this Mac's location.
    public var weatherCity = ""
    /// The open notch lists today's events and what's due from Notion under "TODAY".
    public var showToday = true
    /// Dragging a window onto the notch holds it there (needs Accessibility).
    public var holdWindows = true
    /// One window at a time on each desktop of each display: the window in front fills it and every other one
    /// there is set aside on the sides of the screen (up to 6 per desktop). It won't turn on with more than 7 windows on a
    /// desktop, and turns itself off when a desktop is moved in Mission Control.
    public var quickDock = false
    /// Folders pinned to the Finder tab's sidebar, as paths.
    public var finderPins: [String] = []
    /// The Web tab's start page.
    public var bookmarks: [Bookmark] = []
    /// Sites the Web tab never offers to save a password for (hosts).
    public var passwordNeverSave: [String] = []

    // Display
    /// The display Jarvis's notch is on (`NSScreen`'s vendor-model-serial); empty means this Mac's own.
    public var notchDisplay = ""
    /// On a display without a hardware notch, the bar shows these one at a time; empty leaves it plain black.
    public var tickerItems: [TickerItem] = [.time, .date, .music, .weather, .nextEvent]
    /// Seconds each line shows for.
    public var tickerSeconds = 5.0

    // Connections (keys and tokens live in the Keychain, not here)
    /// Who answers what the local brain can't.
    public var cloudBrain: CloudBrain = .claudeCode
    public var claudeModel = "claude-opus-5-5"
    /// Empty: Codex's own default.
    public var codexModel = ""
    /// Token saving: ask before a question goes to the cloud brain.
    public var askBeforeCloud = false
    /// What Claude may do on this Mac: nothing, Jarvis's tools, or everything (Claude Code's own commands and files).
    public var claudeAccess: ClaudeAccess = .none
    /// Answers small questions on this Mac before anything goes to the cloud.
    public var localBrain: LocalBrain = .apple
    /// The local brain tries everything (writing, maths, code, tools); only news and the camera skip it.
    public var localFirst = true
    /// `LocalModel.id` of the model Jarvis downloads and runs itself.
    public var builtInModelID = LocalModels.recommended().id
    public var ollamaModel = "gemma3:12b"
    public var compatibleBaseURL = "http://localhost:11434/v1"
    public var compatibleModel = "llama3.2"
    /// Saves every question and model call, raw, to Application Support/Jarvis/Logs (see `TurnLog`).
    public var logConversations = false

    // Usage
    public var showTokens = true

    public var hasCompletedWelcome = false

    public init() {}

    /// Decodes saved settings on top of the defaults, so fields added in a
    /// newer version keep their default instead of failing the whole file.
    public static func decode(_ data: Data) throws -> Settings {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any] ?? [:]
        let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let merged = defaults.merging(saved) { _, saved in saved }
        return try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: merged))
    }
}

extension OpenTrigger: Codable {}

public enum ClaudeAccess: String, Codable, Sendable, CaseIterable {
    /// Web search, Notion and the camera, as before.
    case none
    /// Plus Jarvis's tools: apps, windows, Quick Dock, timers and the calendar.
    case tools
    /// Plus, with Claude Code, running commands and reading and editing files, without asking first.
    case full
}

public enum TalkMode: String, Codable, Sendable, CaseIterable {
    case pushToHold, toggle
}

public enum CaptionSize: String, Codable, Sendable, CaseIterable {
    case small, regular, large
}

public enum CloudBrain: String, Codable, Sendable, CaseIterable {
    /// The user's own Claude Code, so their Claude subscription.
    case claudeCode
    /// Claude API with a key.
    case claude
    /// The user's own Codex, so their ChatGPT plan.
    case codex
    case openAICompatible
}

public enum LocalBrain: String, Codable, Sendable, CaseIterable {
    /// Apple's on-device model.
    case apple
    /// A model Jarvis downloads and runs itself (llama.cpp), no other install.
    case builtIn
    /// Ollama running on this Mac.
    case ollama
    case off
}
