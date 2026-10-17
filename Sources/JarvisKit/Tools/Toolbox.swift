import Foundation

/// Jarvis's tools, and which ones a request needs. Plainly worded timers and calendar adds are done by
/// code instantly; anything else goes to the local brain with tools (timers, calendar, Notion), then to
/// the cloud brain if it can't. Schedule questions get the events as context; the camera needs the cloud.
@MainActor
public struct Toolbox {
    public var timers: TimerCenter?
    public var calendar: CalendarSource?
    public var camera: CameraSource?
    /// Opens apps and runs music by plain wording.
    public var apps: AppLauncher?
    /// Notion tools when a token is saved, else nil.
    public var notion: () -> ToolKit?
    /// Opening apps, the notch's window dock and Quick Dock, for the local brain.
    public var mac: MacControls?
    /// For the morning brief and weather questions, answered by code.
    public var weather: WeatherSource?

    public init(timers: TimerCenter? = nil, calendar: CalendarSource? = nil, camera: CameraSource? = nil,
                apps: AppLauncher? = nil, mac: MacControls? = nil, weather: WeatherSource? = nil,
                notion: @escaping () -> ToolKit? = { nil }) {
        self.weather = weather
        self.timers = timers
        self.calendar = calendar
        self.camera = camera
        self.apps = apps
        self.mac = mac
        self.notion = notion
    }

    public static let none = Toolbox()

    /// What the cloud brain needs for a request beyond the text.
    public struct CloudNeeds: Equatable, Sendable {
        public var photo = false
        public var notion = false

        public var any: Bool { photo || notion }
    }

    /// A finished reply from plain code, or nil to let a brain answer. Calendar adds are left to a local
    /// brain that can use tools (`calendar: false`): it reads loose wording like "evening around six" better.
    public func instantReply(_ text: String, calendar useCode: Bool = true, now: Date = .now) -> (text: String, source: String)? {
        if let timers, let reply = timers.handle(text, now: now) { return (reply, "Timer") }
        // After timers ("start a timer" is theirs), before the brains; a request that isn't plainly an app or
        // a song ("open my notion and tell me what's due", "play it") is not claimed.
        if let apps, let reply = apps.handle(text) { return (reply, "Apps") }
        guard useCode, let calendar, CalendarCommand.isAdd(text), let event = CalendarCommand.parseAdd(text, now: now) else {
            return nil
        }
        do {
            let item = try calendar.add(title: event.title, start: event.start, end: event.end, allDay: event.allDay)
            return (CalendarCommand.confirmation(item), "Calendar")
        } catch {
            return (error.localizedDescription, "Calendar")
        }
    }

    /// Timers, reminders or calendar wording: answered from the user's own data, not from the model's memory.
    public func isScheduling(_ text: String) -> Bool {
        (timers != nil || calendar != nil)
            && text.range(of: Self.scheduling, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let scheduling = #"\b(timers?|countdown|alarm|remind(er)?s?|remind me|wake me|calendar|schedule|appointment|event)\b"#
    private static let timerRequest = #"\b(set|start|make)\b.*\b(timer|alarm)\b|\b(remind|wake) me\b"#

    /// The tools a local brain gets: timers, the calendar's reading tool, the Mac tools (apps, window dock, Quick Dock)
    /// and the calculator, whatever the wording, so the model decides what a request needs and no word list has to.
    /// Nothing that adds, changes or deletes, and no Notion: those go to the cloud brain.
    public func localKits(for text: String, needs: CloudNeeds) -> [ToolKit] {
        var kits: [ToolKit] = []
        if let timers { kits.append(TimerTools(center: timers)) }
        if let calendar { kits.append(ReadOnlyKit(CalendarTools(source: calendar), allowed: ["list"])) }
        if let mac { kits.append(MacTools(controls: mac)) }
        kits.append(MathTools())
        return kits
    }

    /// A nudge for a local model, so it reaches for the right tool instead of guessing or giving up.
    public func localHint(for text: String, kits: [ToolKit], needs: CloudNeeds) -> String? {
        var hints: [String] = []
        if kits.contains(where: { $0.name == "calendar" }), text.range(of: #"\b(calendar|schedule|free|busy|meeting|class|lecture)\b"#,
                                                                       options: [.regularExpression, .caseInsensitive]) != nil {
            hints.append("For the calendar, call calendar_list with today's date from the question's note.")
        }
        return hints.isEmpty ? nil : hints.joined(separator: " ")
    }


    /// A change the local brain can't make (add, tick, move, delete...) to something that lives in an app the user can
    /// open: the app's name to offer ("Calendar", or "Notion" only when it's connected), else nil.
    public func openOffer(for text: String) -> String? {
        guard apps != nil, text.range(of: Self.changeWords, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        if calendar != nil, text.range(of: #"\b(calendar|events?|meetings?|appointments?)\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil { return "Calendar" }
        if notion() != nil, text.range(of: Self.notionWords + #"|\b(lists?|pages?)\b"#,
                                       options: [.regularExpression, .caseInsensitive]) != nil { return "Notion" }
        return nil
    }

    private static let changeWords = #"\b(add|put|tick|check off|cross off|mark|move|reschedule|rename|change|create|make|delete|remove|cancel|edit|update|finish|complete)\b"#

    /// What Jarvis says when it offers: it can't do it, and the person is probably quicker.
    public static func offerText(app: String) -> String {
        "I can't make that change myself, and you're probably the better person for the job. Want me to open \(app)?"
    }

    /// Opens an app Jarvis offered, after a yes. Nil when the app can't be opened.
    public func openApp(_ name: String) -> String? { apps?.open(name) }

    /// The cloud brain can't set timers or add events, so these get a hint instead of a made-up "done".
    public func cloudCantDo(_ text: String) -> String? {
        if calendar != nil, CalendarCommand.isAdd(text) {
            return "I couldn't tell when. Try \"add dentist to my calendar tomorrow at 3pm\"."
        }
        if timers != nil, text.range(of: Self.timerRequest, options: [.regularExpression, .caseInsensitive]) != nil {
            return "I couldn't tell when. Try \"timer 10 minutes\", \"remind me in 20 minutes\" or \"remind me at 7 pm to call mom\"."
        }
        return nil
    }

    /// The user's events, put in front of a question about their schedule.
    public func context(for text: String, now: Date = .now) -> String {
        guard let calendar, CalendarCommand.isQuestion(text) else { return "" }
        let range = CalendarCommand.range(for: text, now: now)
        guard let items = calendar.events(from: range.start, to: range.end) else {
            return "(Jarvis can't see the user's calendar: Calendar access is off.) "
        }
        return CalendarCommand.context(items, start: range.start, end: range.end)
    }

    /// Notion when named, or for due dates, assignments and to-do lists when a token is saved.
    private static let notionWords = #"\b(notion|due|deadlines?|assignments?|homework|problem sets?|to-?do|todo list|tasks?|midterms?|exams?|tests?|quiz(zes)?)\b"#

    public func needs(_ text: String) -> CloudNeeds {
        let named = text.range(of: #"\bnotion\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let sounds = text.range(of: Self.notionWords, options: [.regularExpression, .caseInsensitive]) != nil
        return CloudNeeds(photo: camera != nil && MacCamera.matches(text), notion: named || (sounds && notion() != nil))
    }

    /// What the cloud brain can use on this Mac when Claude's access allows tools: the apps, window dock and Quick Dock,
    /// timers, and the whole calendar (adding, moving and deleting too). Nil when none of them is set up.
    public func cloudMacKit() -> ToolKit? {
        var kits: [ToolKit] = []
        if let mac { kits.append(MacTools(controls: mac)) }
        if let timers { kits.append(TimerTools(center: timers)) }
        if let calendar { kits.append(CalendarTools(source: calendar)) }
        return kits.isEmpty ? nil : CombinedKit(kits)
    }

    /// Takes the photo and loads the tools a request needs, and what Claude's access allows.
    public func extras(for needs: CloudNeeds, access: ClaudeAccess = .none) async throws -> ChatExtras {
        var extras = ChatExtras()
        if access != .none { extras.mac = cloudMacKit() }
        extras.computer = access == .full
        if needs.notion {
            guard let kit = notion() else {
                throw ChatError("Add a Notion token in Settings › Connections first, then share your pages with it in Notion.")
            }
            extras.tools = kit
        }
        if needs.photo, let camera { extras.image = try await camera.snapshot() }
        return extras
    }
}
