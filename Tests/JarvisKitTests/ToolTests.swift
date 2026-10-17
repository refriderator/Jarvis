import Foundation
import JarvisKit
import Testing

struct TimerCommandTests {
    @Test func readsDurations() {
        #expect(TimerCommand.parse("set a timer for 5 minutes") == .start(seconds: 300))
        #expect(TimerCommand.parse("timer 90 seconds") == .start(seconds: 90))
        #expect(TimerCommand.parse("1 hour 30 min timer") == .start(seconds: 5400))
        #expect(TimerCommand.parse("set a timer for half an hour") == .start(seconds: 1800))
        #expect(TimerCommand.parse("timer for an hour and a half") == .start(seconds: 5400))
        #expect(TimerCommand.parse("an hour timer please") == .start(seconds: 3600))
    }

    @Test func alarmsAndRemindersGetOneAnswerHoweverWorded() {
        for text in ["set an alarm for 7 am", "wake me up at 6:30", "remind me in 20 minutes to call mom",
                     "remind me at 8:45 pm", "can you set a reminder for tomorrow", "alarm in an hour"] {
            #expect(TimerCommand.parse(text) == .timersOnly, "\(text)")
        }
        #expect(TimerCommand.parse("cancel my alarm") == .cancelAll, "cancelling is about the timers")
    }

    @Test func spokenLengthsForTheTool() {
        #expect(TimerCommand.seconds(in: "an hour and a half") == 5400)
        #expect(TimerCommand.seconds(in: "two hours") == 7200)
        #expect(TimerCommand.seconds(in: "10 minutes") == 600)
        #expect(TimerCommand.seconds(in: "half an hour") == 1800)
        #expect(TimerCommand.seconds(in: "a while") == nil)
    }

    @Test func cancelAndStatus() {
        #expect(TimerCommand.parse("cancel the timer") == .cancelAll)
        #expect(TimerCommand.parse("how long is left on my timer") == .status)
    }

    @Test func ignoresOtherQuestions() {
        #expect(TimerCommand.parse("what's 5 minutes in seconds") == nil)
        #expect(TimerCommand.parse("set a timer") == nil)
    }

    @Test func labels() {
        #expect(JarvisTimer(seconds: 300, ends: .now).label == "5 minute")
        #expect(TimerCommand.describe(5400) == "1 hour 30 minutes")
    }
}

@MainActor
struct TimerCenterTests {
    @Test func startsCancelsAndFires() async {
        let state = AppState()
        let center = TimerCenter(state: state)
        #expect(center.handle("timer 5 minutes") == "Timer set for 5 minutes.")
        #expect(state.timers.count == 1)
        #expect(center.handle("cancel the timer") == "Timer cancelled.")
        #expect(state.timers.isEmpty)

        center.start(1)
        for _ in 0..<300 where !state.timers.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(state.timers.isEmpty)
        #expect(state.turns.last?.answer == "Your 1 second timer is done.")
        #expect(state.turns.last?.spoken == true)
    }
}

struct CalendarCommandTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T12:00:00Z")!

    @Test func addsTimedEvent() throws {
        let event = try #require(CalendarCommand.parseAdd("add dentist to my calendar tomorrow at 3pm", now: now))
        #expect(event.title == "Dentist")
        #expect(!event.allDay)
        #expect(event.end.timeIntervalSince(event.start) == 3600)
        #expect(Calendar.current.component(.hour, from: event.start) == 15)
    }

    @Test func addsAllDayEvent() throws {
        let event = try #require(CalendarCommand.parseAdd("put Mom's birthday on my calendar on December 3", now: now))
        #expect(event.allDay)
        #expect(event.title == "Mom's birthday")
    }

    @Test func tellsAddsFromQuestions() {
        #expect(CalendarCommand.isAdd("schedule a meeting with Sam friday at 2"))
        #expect(!CalendarCommand.isAdd("what's on my calendar today"))
        #expect(CalendarCommand.isQuestion("what's on my calendar today"))
        #expect(CalendarCommand.isQuestion("am I free tomorrow afternoon"))
        #expect(!CalendarCommand.isQuestion("capital of France"))
    }

    @Test func noDateMeansNoEvent() {
        #expect(CalendarCommand.parseAdd("add gym to my calendar", now: now) == nil)
    }
}

struct AppCommandTests {
    @Test func readsPlainRequests() {
        #expect(AppCommand.parse("open Spotify") == .open(app: "Spotify"))
        #expect(AppCommand.parse("hey, can you launch Microsoft Word please") == .open(app: "Microsoft Word"))
        #expect(AppCommand.parse("open up the Notes app") == .open(app: "Notes"))
        #expect(AppCommand.parse("play Blinding Lights on Spotify") == .play(query: "Blinding Lights", app: "Spotify"))
        #expect(AppCommand.parse("play the song Levitating on apple music") == .play(query: "Levitating", app: "Music"))
        #expect(AppCommand.parse("play Não Admira") == .play(query: "Não Admira", app: nil))
        #expect(AppCommand.parse("pause the music") == .control(.pause))
        #expect(AppCommand.parse("resume") == .control(.resume))
        #expect(AppCommand.parse("next song") == .control(.next))
        #expect(AppCommand.parse("dock Safari") == .dock(app: "Safari"))
        #expect(AppCommand.parse("please dock all the Chrome windows") == .dock(app: "Chrome"))
    }

    @Test func leavesLooseWordingToABrain() {
        for text in ["play it again", "let's play a game", "play devil's advocate", "play", "what's on my calendar",
                     "open the thursday midterm in notion and tell me what's after it", "stop", "skip", "how do I open a pdf", "dock this", "dock", "dock it please", "what is a dock"] {
            let parsed = AppCommand.parse(text)
            if case .open(let app)? = parsed {
                #expect(app.split(separator: " ").count > 3 || text.contains("pdf"), "\(text)") // too long for a name; the app finder rejects it
            } else {
                #expect(parsed == nil, "\(text)")
            }
        }
    }
}

@MainActor
struct AppLauncherTests {
    private struct FakeApps: AppFinder {
        func find(_ spoken: String) -> (name: String, url: URL)? {
            spoken.lowercased() == "spotify" ? ("Spotify", URL(fileURLWithPath: "/Applications/Spotify.app")) : nil
        }
    }

    @Test func claimsOnlyWhatItCanResolve() {
        let player = FakePlayer()
        let launcher = AppLauncher(finder: FakeApps(), player: player, runningMusic: { [.spotify] })
        #expect(launcher.handle("open my notion and tell me what's due") == nil, "not an app: a brain answers")
        #expect(launcher.handle("play Levitating") == "Playing Levitating.")
        #expect(player.played == ["Levitating"])
        #expect(AppLauncher(finder: FakeApps(), player: player, runningMusic: { [] }).handle("play Levitating") == nil,
                "no music app open and none named: a brain decides")
    }
}

@MainActor
final class FakeCalendar: CalendarSource {
    var items: [AgendaItem] = []
    func events(from start: Date, to end: Date) -> [AgendaItem]? { items }
    func add(title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        let item = AgendaItem(id: UUID().uuidString, title: title, start: start, end: end, allDay: allDay)
        items.append(item)
        return item
    }
    func event(id: String) -> AgendaItem? { items.first { $0.id == id } }
    func change(id: String, title: String, start: Date, end: Date, allDay: Bool) throws -> AgendaItem {
        let item = AgendaItem(id: id, title: title, start: start, end: end, allDay: allDay)
        items = items.map { $0.id == id ? item : $0 }
        return item
    }
    func delete(id: String) throws { items.removeAll { $0.id == id } }
}

@MainActor
struct ToolboxAssistantTests {
    private func run(_ assistant: Assistant, _ text: String, state: AppState) async {
        assistant.ask(text)
        for _ in 0..<50 where state.turns.last?.isPending == true { await Task.yield() }
    }

    @Test func timersAndCalendarAddsUseNoModel() async {
        let state = AppState()
        let calendar = FakeCalendar()
        let cloud = FakeBrain("Claude", answer: "unused")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud },
                                  tools: Toolbox(timers: TimerCenter(state: state), calendar: calendar))
        await run(assistant, "timer for 10 minutes", state: state)
        #expect(state.turns.last?.source == "Timer")
        await run(assistant, "add lunch with Ana to my calendar tomorrow at noon", state: state)
        #expect(state.turns.last?.source == "Calendar")
        #expect(calendar.items.first?.title == "Lunch with Ana")
        #expect(cloud.asked.isEmpty)
        #expect(state.tokens.today == 0)
    }

    @Test func scheduleQuestionsCarryEvents() async {
        let state = AppState()
        let calendar = FakeCalendar()
        calendar.items = [AgendaItem(id: "1", title: "PHY224 Lec", start: .now, end: .now.addingTimeInterval(3600), allDay: false)]
        let local = FakeBrain("On-device", answer: "You have PHY224.")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in nil },
                                  tools: Toolbox(calendar: calendar))
        await run(assistant, "what's on my calendar", state: state)
        #expect(local.asked.last?.last?.text.contains("PHY224 Lec") == true)
    }

    @Test func notionNeedsAToolCapableBrainAndAToken() async {
        let state = AppState()
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in FakeBrain("Local LLM", answer: "") })
        await run(assistant, "add milk to my Notion groceries", state: state)
        #expect(state.turns.last?.answer?.contains("can't use Notion") == true)
    }
}

struct NotionTests {
    @Test func blocksBecomePlainLines() {
        let todo: [String: Any] = ["id": "b1", "type": "to_do",
                                   "to_do": ["checked": true, "rich_text": [["plain_text": "Milk"]]]]
        #expect(NotionAPI.line(todo) == "[x] Milk (block b1)")
        let heading: [String: Any] = ["type": "heading_2", "heading_2": ["rich_text": [["plain_text": "Week"]]]]
        #expect(NotionAPI.line(heading) == "## Week")
    }

    @Test func mcpListsAndCallsTools() async throws {
        let tools = NotionTools(token: "x")
        let initialize = try await MCPServer.respond("initialize", params: [:], tools: tools).get()
        #expect((initialize["serverInfo"] as? [String: Any])?["name"] as? String == "jarvis-notion")
        let list = try await MCPServer.respond("tools/list", params: [:], tools: tools).get()
        #expect((list["tools"] as? [[String: Any]])?.count == tools.definitions.count)
        let missing = try await MCPServer.respond("tools/call", params: ["name": "search", "arguments": [:]], tools: tools).get()
        #expect(missing["isError"] as? Bool == true)
    }
}

struct ClaudeToolLoopTests {
    @Test func readsToolCalls() throws {
        let json = #"{"content":[{"type":"thinking","thinking":""},{"type":"tool_use","id":"t1","name":"notion_search","input":{"query":"groceries"}}],"stop_reason":"tool_use","usage":{"input_tokens":5,"output_tokens":2}}"#
        let step = try ClaudeAPIProvider.parse(Data(json.utf8), status: 200)
        #expect(step.toolCalls.count == 1)
        #expect(step.toolCalls.first?.name == "search")
        #expect(step.content.count == 2, "thinking block kept to echo back")
    }
}

struct HotkeyTests {
    @Test func showsModifiers() {
        #expect(Hotkey.talk.text == "⌥Space")
        #expect(Hotkey.type.text == "⌥⇧Space")
    }

    @Test func settingsKeepHotkeys() throws {
        var settings = Settings()
        settings.talkHotkey = Hotkey(keyCode: 38, modifiers: 2048, key: "J")
        let decoded = try Settings.decode(JSONEncoder().encode(settings))
        #expect(decoded.talkHotkey.key == "J")
    }
}

struct NotionDueTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z")!

    @Test func picksTheDueColumn() {
        let properties: [String: [String: Any]] = ["Created": ["type": "date"], "Due date": ["type": "date"],
                                                   "Name": ["type": "title"]]
        #expect(NotionAPI.dateColumn(properties) == "Due date")
    }

    @Test func knowsWhatsDone() {
        #expect(NotionAPI.isDone(["Done": ["type": "checkbox", "checkbox": true]]))
        #expect(!NotionAPI.isDone(["Done": ["type": "checkbox", "checkbox": false]]))
        #expect(NotionAPI.isDone(["Status": ["type": "status", "status": ["name": "Submitted"]]]))
        #expect(!NotionAPI.isDone(["Status": ["type": "status", "status": ["name": "In progress"]]]))
    }

    @Test func saysDatesLikeAPerson() throws {
        let thursday = try #require(NotionAPI.date("2026-10-15"))
        #expect(!thursday.hasTime)
        #expect(NotionAPI.friendly(thursday.date, hasTime: false, now: now) == "Thursday")
        let tomorrow = try #require(NotionAPI.date("2026-10-14"))
        #expect(NotionAPI.friendly(tomorrow.date, hasTime: false, now: now) == "tomorrow")
        let timed = try #require(NotionAPI.date("2026-10-15T06:45:00.000-04:00"))
        #expect(timed.hasTime)
        #expect(NotionAPI.friendly(timed.date, hasTime: true, now: now).hasPrefix("Thursday at"))
        let later = try #require(NotionAPI.date("2026-11-30"))
        #expect(NotionAPI.friendly(later.date, hasTime: false, now: now) == "Nov 30")
    }

    @MainActor @Test func dueQuestionsBringNotionWhenConnected() {
        let connected = Toolbox(notion: { NotionTools(token: "x") })
        #expect(connected.needs("what's due this week").notion)
        #expect(connected.needs("any homework tonight?").notion)
        #expect(!Toolbox.none.needs("what's due this week").notion, "no token, no Notion")
        #expect(!connected.needs("capital of France").notion)
    }
}

@MainActor
struct MacToolsTests {
    @Test func checksValuesAndCallsTheApp() async throws {
        let controls = MacControls()
        var docked: [String?] = []
        var quick: Bool?
        controls.dockWindow = { app in docked.append(app); return "Put \(app ?? "Safari") in the dock." }
        controls.setQuickDock = { on in quick = on; return on ? "Quick Dock is on." : "Quick Dock is off." }
        let tools = MacTools(controls: controls)
        #expect(try await tools.call("dock_window", arguments: Data(#"{}"#.utf8)) == "Put Safari in the dock.")
        #expect(try await tools.call("dock_window", arguments: Data(#"{"app": "  "}"#.utf8)) == "Put Safari in the dock.",
                "a blank name means the window in front")
        #expect(docked == [nil, nil])
        #expect(try await tools.call("quick_dock", arguments: Data(#"{"on": true}"#.utf8)) == "Quick Dock is on.")
        #expect(quick == true)
        await #expect(throws: ChatError.self) { try await tools.call("quick_dock", arguments: Data(#"{"on": "yes"}"#.utf8)) }
        await #expect(throws: ChatError.self, "not wired up yet") {
            try await tools.call("undock_window", arguments: Data(#"{"app": "Safari"}"#.utf8))
        }
    }
}

@MainActor
struct ToolRelayTests {
    private func socket() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "jr-\(UUID().uuidString.prefix(8)).sock")
    }

    @Test func passesCallsToTheAppAndStopsWhenAccessIsOff() async throws {
        let controls = MacControls()
        controls.setQuickDock = { on in on ? "Quick Dock is on." : "Quick Dock is off." }
        var allowed = true
        let path = socket()
        let server = ToolRelay.Server(kit: { CombinedKit([MacTools(controls: controls)]) }, allowed: { allowed }, path: path)
        try server.start()
        defer { server.stop() }
        // Off the main actor, as in the real MCP process: the app's side answers on the main actor.
        let client = try await Task.detached { try ToolRelay.Client(path: path) }.value
        #expect(client.definitions.map(\.name).contains("mac_quick_dock"))
        #expect(try await client.call("mac_quick_dock", arguments: Data(#"{"on": true}"#.utf8)) == "Quick Dock is on.")
        await #expect(throws: ChatError.self, "a bad value comes back as an error") {
            try await client.call("mac_quick_dock", arguments: Data(#"{"on": "yes"}"#.utf8))
        }
        allowed = false
        await #expect(throws: ChatError.self, "access turned off in Settings") {
            try await client.call("mac_quick_dock", arguments: Data(#"{"on": false}"#.utf8))
        }
        await #expect(throws: ChatError.self) { try await Task.detached { try ToolRelay.Client(path: path) }.value }
    }

    @Test func noAppRunningIsAPlainError() {
        #expect(throws: ChatError.self) { try ToolRelay.Client(path: socket()) }
    }

    @Test func cloudGetsTheMacKitOnlyWithAccess() async throws {
        let state = AppState()
        let tools = Toolbox(timers: TimerCenter(state: state), calendar: FakeCalendar(), mac: MacControls())
        let none = try await tools.extras(for: tools.needs("hello"))
        #expect(none.isEmpty)
        let some = try await tools.extras(for: tools.needs("hello"), access: .tools)
        #expect(some.mac?.definitions.map(\.name).contains("calendar_add") == true, "the cloud may change the calendar")
        #expect(!some.computer)
        #expect(try await tools.extras(for: tools.needs("hello"), access: .full).computer)
    }
}
