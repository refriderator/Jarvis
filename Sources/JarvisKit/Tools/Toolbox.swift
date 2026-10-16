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

    public init(timers: TimerCenter? = nil, calendar: CalendarSource? = nil, camera: CameraSource? = nil,
                apps: AppLauncher? = nil, notion: @escaping () -> ToolKit? = { nil }) {
        self.timers = timers
        self.calendar = calendar
        self.camera = camera
        self.apps = apps
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

    /// The tools a local brain gets: every tool that is set up (Notion when a token is saved, timers, calendar)
    /// plus the calculator,
    /// whatever the wording, so the model decides what a request needs and no word list has to.
    /// Throws if Notion is clearly wanted but no token is saved.
    public func localKits(for text: String, needs: CloudNeeds) throws -> [ToolKit] {
        var kits: [ToolKit] = []
        if let kit = notion() {
            kits.append(kit)
        } else if needs.notion {
            throw ChatError("Add a Notion token in Settings › Connections first, then share your pages with it in Notion.")
        }
        if let timers { kits.append(TimerTools(center: timers)) }
        if let calendar { kits.append(CalendarTools(source: calendar)) }
        kits.append(MathTools())
        return kits
    }

    /// A nudge for a local model, so it reaches for the right tool instead of guessing or giving up.
    /// Only questions that sound like Notion get a Notion hint; for the rest the model judges from the tool list.
    public func localHint(for text: String, kits: [ToolKit], needs: CloudNeeds) -> String? {
        var hints: [String] = []
        if needs.notion, kits.contains(where: { $0.name == "notion" }) {
            if text.range(of: Self.dueWords, options: [.regularExpression, .caseInsensitive]) != nil {
                hints.append("The question is about what's due or to do: call notion_due first (it lists everything unfinished "
                             + "with its date, exams and coursework apart, each soonest first), then answer from its result. Use days 7 for \"this week\", 1 for \"today\". "
                             + "For \"next\", \"after\" or \"before\" questions use days 60, find the item the user named in the list, "
                             + "then answer with the next matching item below it.")
            } else {
                hints.append("The question is about Notion: to tick something off a list call notion_tick; otherwise call "
                             + "notion_search first, then notion_read_page.")
            }
        }
        if kits.contains(where: { $0.name == "calendar" }), text.range(of: #"\b(calendar|schedule|free|busy|meeting|class|lecture)\b"#,
                                                                       options: [.regularExpression, .caseInsensitive]) != nil {
            hints.append("For the calendar, call calendar_list with today's date from the question's note.")
        }
        return hints.isEmpty ? nil : hints.joined(separator: " ")
    }

    private static let dueWords = #"\b(due|deadlines?|assignments?|homework|problem sets?|to-?do|todo list|tasks?|midterms?|exams?|tests?|quiz(zes)?)\b"#

    /// The cloud brain can't set timers or add events, so these get a hint instead of a made-up "done".
    public func cloudCantDo(_ text: String) -> String? {
        if calendar != nil, CalendarCommand.isAdd(text) {
            return "I couldn't tell when. Try \"add dentist to my calendar tomorrow at 3pm\"."
        }
        if timers != nil, text.range(of: Self.timerRequest, options: [.regularExpression, .caseInsensitive]) != nil {
            return "I couldn't tell how long. Try \"timer 10 minutes\" or \"remind me in 20 minutes\"."
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

    /// Takes the photo and loads the tools a request needs.
    public func extras(for needs: CloudNeeds) async throws -> ChatExtras {
        var extras = ChatExtras()
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
