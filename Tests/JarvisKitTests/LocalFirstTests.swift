import Foundation
import JarvisKit
import Testing

/// A local model that replies with each scripted answer in turn and can use tools.
@MainActor
final class ScriptedBrain: ChatProvider {
    let label = "Qwen3 8B"
    var canUseTools: Bool { true }
    var answers: [String]
    var asked: [[ChatMessage]] = []

    init(_ answers: [String]) {
        self.answers = answers
    }

    func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        asked.append(history)
        return ChatReply(text: answers.isEmpty ? "ESCALATE" : answers.removeFirst(), inputTokens: 10, outputTokens: 5)
    }
}

struct LocalFirstRouterTests {
    @Test func bigTasksStayLocalButNewsDoesNot() {
        #expect(Router.decide("write an email to my prof", localAvailable: true, preferLocal: true).route == .local)
        #expect(Router.decide("solve x^2 = 4", localAvailable: true, preferLocal: true).route == .local)
        #expect(Router.decide("who won the game last night", localAvailable: true, preferLocal: true).route == .cloud)
        #expect(Router.decide("what's due this week", localAvailable: true, preferLocal: true).route == .cloud,
                "without tools, 'this week' still means news")
        #expect(Router.decide("what's due this week", localAvailable: true, preferLocal: true, hasTools: true).route == .local)
        #expect(Router.decide("write an email to my prof", localAvailable: true).route == .cloud)
    }

    @Test func readsToolCallsInEveryWrapping() {
        #expect(LocalToolLoop.parseCall(#"{"tool": "timer_start", "arguments": {"seconds": 60}}"#)?.tool == "timer_start")
        #expect(LocalToolLoop.parseCall("```json\n{\"tool\": \"notion_search\", \"arguments\": {}}\n```")?.tool == "notion_search")
        #expect(LocalToolLoop.parseCall(#"<tool_call>{"name": "calendar_add", "arguments": {}}</tool_call>"#)?.tool == "calendar_add")
        #expect(LocalToolLoop.parseCall("Paris.") == nil)
        // Real Qwen3 4B output: one brace too many.
        #expect(LocalToolLoop.parseCall(#"{"tool": "timer_start", "arguments": {"seconds": 1200, "note": "a } b"}}}"#)?.tool == "timer_start")
    }
}

@MainActor
struct ToolValidationTests {
    private func start(_ input: [String: Any]) async -> [JarvisTimer] {
        let state = AppState()
        let tools = TimerTools(center: TimerCenter(state: state))
        _ = try? await tools.call("start", arguments: JSONSerialization.data(withJSONObject: input))
        return state.timers
    }

    @Test func timerRefusesNonsense() async {
        #expect(await start(["seconds": 0]).isEmpty)
        #expect(await start(["seconds": 999_999]).isEmpty)
        #expect(await start(["at": "25:00"]).isEmpty)
        #expect(await start(["seconds": 90]).first?.seconds == 90)
    }

    @Test func calculatorIsExactAndRefusesNonsense() async throws {
        func calc(_ expression: String) async throws -> String {
            try await MathTools().call("calculate", arguments: JSONSerialization.data(withJSONObject: ["expression": expression]))
        }
        #expect(try await calc("38*60") == "38*60 = 2280")
        #expect(try await calc("(12 + 7) / 4") == "(12 + 7) / 4 = 4.75")
        #expect(try await calc("15% * 200") == "15% * 200 = 30")
        #expect(try await calc("1,000 - 2^3") == "1,000 - 2^3 = 992")
        #expect(try await calc("10/3") == "10/3 = 3.333333")
        await #expect(throws: ChatError.self) { try await calc("15% of 200") }
        await #expect(throws: ChatError.self) { try await calc("1/0") }
        await #expect(throws: ChatError.self) { try await calc("(2+3") }
    }

    @Test func calendarChangesNeedARealIdAndDeletesTheRightTitle() async throws {
        let calendar = FakeCalendar()
        let start = Date.now.addingTimeInterval(86_400)
        let dentist = try calendar.add(title: "Dentist", start: start, end: start.addingTimeInterval(3600), allDay: false)
        let tools = CalendarTools(source: calendar)
        func input(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

        await #expect(throws: ChatError.self) { try await tools.call("change", arguments: input(["id": "made-up", "title": "X"])) }
        _ = try await tools.call("change", arguments: input(["id": dentist.id, "minutes": 30]))
        #expect(calendar.items.first?.end == start.addingTimeInterval(1800), "start kept, length changed")
        await #expect(throws: ChatError.self) { try await tools.call("delete", arguments: input(["id": dentist.id, "title": "gym"])) }
        #expect(calendar.items.count == 1, "a wrong title deletes nothing")
        _ = try await tools.call("delete", arguments: input(["id": dentist.id, "title": "dentist"]))
        #expect(calendar.items.isEmpty)
    }

    @Test func calendarRefusesBadDates() async {
        let tools = CalendarTools(source: FakeCalendar())
        for start in ["tomorrow", "1999-01-01 10:00", "2026-13-40"] {
            let input = try! JSONSerialization.data(withJSONObject: ["title": "X", "start": start])
            await #expect(throws: ChatError.self) { try await tools.call("add", arguments: input) }
        }
    }
}

@MainActor
struct LocalToolAssistantTests {
    private func run(_ assistant: Assistant, _ text: String, state: AppState) async {
        assistant.ask(text)
        for _ in 0..<200 where state.turns.last?.isPending == true { await Task.yield() }
    }

    @Test func qwenSetsAReminderWithTheTimerTool() async {
        let state = AppState()
        let qwen = ScriptedBrain([#"{"tool": "timer_start", "arguments": {"seconds": 1200, "note": "check the laundry"}}"#,
                                  "Done, I'll remind you in 20 minutes."])
        let cloud = FakeBrain("Claude", answer: "unused")
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in cloud },
                                  tools: Toolbox(timers: TimerCenter(state: state)))
        await run(assistant, "remind me to check the laundry in like twenty-ish minutes", state: state)
        #expect(state.timers.first?.seconds == 1200)
        #expect(state.timers.first?.note == "check the laundry")
        #expect(state.turns.last?.answer == "Done, I'll remind you in 20 minutes.")
        #expect(state.turns.last?.source == "Qwen3 8B")
        #expect(cloud.asked.isEmpty)
    }

    @Test func badValuesGoBackToQwenNotIntoATimer() async {
        let state = AppState()
        let qwen = ScriptedBrain([#"{"tool": "timer_start", "arguments": {"seconds": -5}}"#, "ESCALATE"])
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in nil },
                                  tools: Toolbox(timers: TimerCenter(state: state)))
        await run(assistant, "set a timer for when the pasta is done", state: state)
        #expect(state.timers.isEmpty)
        #expect(qwen.asked.last?.last?.text.contains("Error") == true)
        #expect(state.turns.last?.answer?.contains("timer 10 minutes") == true, "cloud can't set timers, so a hint")
    }

    @Test func calendarAddsArePlainCodeNotQwen() async {
        let state = AppState()
        let calendar = FakeCalendar()
        let qwen = ScriptedBrain(["unused"])
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in nil },
                                  tools: Toolbox(calendar: calendar))
        await run(assistant, "put study group in my calendar tomorrow at 6pm", state: state)
        #expect(calendar.items.first?.title == "Study group")
        #expect(Calendar.current.component(.hour, from: calendar.items.first?.start ?? .distantPast) == 18)
        #expect(qwen.asked.isEmpty)
        // A time it can't read isn't guessed into an all-day event.
        await run(assistant, "put gym in my calendar tomorrow evening around six", state: state)
        #expect(calendar.items.count == 1)
    }

    private struct NoApps: AppFinder {
        func find(_ spoken: String) -> (name: String, url: URL)? { nil }
    }

    @Test func aChangeItCantMakeOffersToOpenTheAppThenWaitsForYes() async {
        let state = AppState()
        let qwen = ScriptedBrain(["ESCALATE"])
        let cloud = FakeBrain("Claude", answer: "unused")
        let tools = Toolbox(calendar: FakeCalendar(), apps: AppLauncher(finder: NoApps(), player: FakePlayer()))
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in cloud }, tools: tools)
        await run(assistant, "move my study group on my calendar to a better time", state: state)
        #expect(state.turns.last?.answer?.contains("better person for the job") == true)
        #expect(state.turns.last?.answer?.contains("open Calendar?") == true)
        #expect(cloud.asked.isEmpty, "the cloud brain can't reach the calendar, so it isn't asked")
        // "no" is answered by code, not sent to a brain; "yes" tries the app (none installed here, so it says so).
        await run(assistant, "no thanks", state: state)
        #expect(state.turns.last?.answer == "Okay.")
        await run(assistant, "move my study group on my calendar to a better time", state: state)
        await run(assistant, "yes please", state: state)
        #expect(state.turns.last?.answer == "I couldn't open Calendar.")
        #expect(qwen.asked.count == 2, "only the two requests reached the local brain")
    }

    @Test func noOfferForReadsOrForNotionThatIsntConnected() {
        let tools = Toolbox(calendar: FakeCalendar(), apps: AppLauncher(finder: NoApps(), player: FakePlayer()))
        #expect(tools.openOffer(for: "what's on my calendar tomorrow") == nil)
        #expect(tools.openOffer(for: "tick off rice on my groceries list") == nil, "Notion isn't connected")
        #expect(tools.openOffer(for: "delete my dentist event") == "Calendar")
    }

    @Test func aModelGoingRoundInCirclesIsNotShownAsAnAnswer() async {
        let state = AppState()
        let call = #"{"tool": "calendar_list", "arguments": {"start": "2026-10-17", "end": "2026-10-18"}}"#
        let qwen = ScriptedBrain([call, call, call])
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in nil },
                                  tools: Toolbox(calendar: FakeCalendar()))
        await run(assistant, "what do i have tomorrow", state: state)
        #expect(qwen.asked.count == 2, "the repeated call is stopped, not run again")
        #expect(state.turns.last?.failed == true, "no raw tool result passed off as the answer")
    }

    @Test func qwenCanOnlyReadTheCalendar() async {
        let state = AppState()
        let calendar = FakeCalendar()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let day = tomorrow.formatted(.iso8601.year().month().day())
        let qwen = ScriptedBrain([#"{"tool": "calendar_add", "arguments": {"title": "Study group", "start": "\#(day) 18:00"}}"#,
                                  "ESCALATE"])
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in nil },
                                  tools: Toolbox(calendar: calendar))
        await run(assistant, "move my study group to a better time", state: state)
        #expect(calendar.items.isEmpty, "the local brain only gets reading tools")
        #expect(qwen.asked.last?.last?.text.contains("isn't available") == true)
    }

    @Test func qwenWritesTheEmailItself() async {
        let state = AppState()
        let qwen = ScriptedBrain(["Hi Professor, could we meet Thursday?"])
        let cloud = FakeBrain("Claude", answer: "unused")
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in cloud })
        await run(assistant, "write an email to my prof asking to meet", state: state)
        #expect(state.turns.last?.source == "Qwen3 8B")
        #expect(cloud.asked.isEmpty)
    }

    @Test func unsureQwenStillHandsOff() async {
        let state = AppState()
        let qwen = ScriptedBrain(["ESCALATE"])
        let cloud = FakeBrain("Claude", answer: "Here's the proof.")
        let assistant = Assistant(state: state, makeLocal: { _ in qwen }, makeCloud: { _ in cloud })
        await run(assistant, "prove there are infinitely many primes", state: state)
        #expect(state.turns.last?.source == "Claude · local unsure")
    }
}

/// Runs a real model through the tool loop; only when `JARVIS_TEST_GGUF` points at a Qwen .gguf file.
@MainActor
struct RealQwenToolTests {
    final class PathBrain: ChatProvider {
        let label = "Qwen"
        var canUseTools: Bool { true }
        let engine = LlamaEngine()
        let path: String
        init(_ path: String) { self.path = path }
        func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
            let result = try await engine.generate(modelPath: path, messages: [("system", system + " /no_think")]
                + history.map { ($0.role.rawValue, $0.text) })
            print("QWEN:", result.text.replacingOccurrences(of: "\n", with: " "))
            return ChatReply(text: result.text, inputTokens: result.input, outputTokens: result.output)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"] != nil))
    func realQwenUsesTools() async throws {
        let brain = PathBrain(try #require(ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"]))
        let state = AppState()
        let calendar = FakeCalendar()
        let kits: [ToolKit] = [TimerTools(center: TimerCenter(state: state)), CalendarTools(source: calendar)]
        for text in ["remind me to check the laundry in twenty minutes",
                     "put study group in my calendar for tomorrow evening around six"] {
            let reply = try await LocalToolLoop.run(brain, history: [ChatMessage(.user, Persona.context() + text)], kits: kits)
            print("ANSWER:", reply.text)
        }
        await brain.engine.unload()
        print("TIMERS:", state.timers.map { "\($0.seconds)s \($0.note ?? "")" })
        print("EVENTS:", calendar.items.map { "\($0.title) \($0.start.formatted()) allDay=\($0.allDay)" })
        #expect(state.timers.first?.seconds == 1200)
        #expect(calendar.items.count == 1)
    }
}

/// A stand-in Notion with canned due items, to see whether the real model calls the right tool.
struct CannedNotion: ToolKit {
    let name = "notion"
    var instructions: String { "" }
    var definitions: [ToolDefinition] { NotionTools(token: "x").definitions }
    func call(_ name: String, arguments: Data) async throws -> String {
        NotionCalls.shared.record(name)
        guard name == "due" else { return "Nothing found." }
        return "- MAT244 Online PS — due Thursday (Assignments, id a1)\n- PHY224 Notebook — due Thursday at 6:45 AM (Assignments, id a2)\n"
            + "- PHY254 PS2 — due Sunday at midnight (Assignments, id a3)"
    }
}

final class NotionCalls: @unchecked Sendable {
    static let shared = NotionCalls()
    private let lock = NSLock()
    private var names: [String] = []
    func record(_ name: String) { lock.withLock { names.append(name) } }
    var all: [String] { lock.withLock { names } }
}

@MainActor
struct RealQwenNotionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"] != nil))
    func realQwenCallsDueForDueQuestions() async throws {
        let brain = RealQwenToolTests.PathBrain(try #require(ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"]))
        let box = Toolbox(notion: { CannedNotion() })
        for question in ["what's due this week", "any homework I need to do?", "what tasks do I have"] {
            let needs = box.needs(question)
            #expect(needs.notion)
            let kits = box.localKits(for: question, needs: needs)
            let decision = Router.decide(question, localAvailable: true, preferLocal: true, hasTools: true)
            #expect(decision.route == .local, "\(question)")
            let reply = try await LocalToolLoop.run(brain, history: [ChatMessage(.user, Persona.context() + question)],
                                                    kits: kits, hint: box.localHint(for: question, kits: kits, needs: needs))
            print("Q:", question, "→", reply.text.replacingOccurrences(of: "\n", with: " "))
        }
        await brain.engine.unload()
        print("TOOLS CALLED:", NotionCalls.shared.all)
        #expect(NotionCalls.shared.all.filter { $0 == "due" }.count >= 3)
    }
}

struct CodexProviderTests {
    @Test func readsTheAnswerAndTokensFromItsEvents() throws {
        let events = """
            {"type":"thread.started","thread_id":"t"}
            {"type":"item.completed","item":{"id":"1","type":"reasoning","text":"thinking"}}
            {"type":"item.completed","item":{"id":"2","type":"agent_message","text":"Paris."}}
            {"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":800,"output_tokens":12,"reasoning_output_tokens":4}}
            """
        let reply = try CodexProvider.parse(Data(events.utf8))
        #expect(reply.text == "Paris.")
        #expect(reply.inputTokens == 1200 && reply.outputTokens == 12)
    }

    @Test func aFailedTurnSaysWhy() {
        let events = #"{"type":"turn.failed","error":{"message":"You've hit your usage limit."}}"#
        #expect(throws: ChatError("Codex: You've hit your usage limit.")) { try CodexProvider.parse(Data(events.utf8)) }
        #expect(throws: ChatError.self) { try CodexProvider.parse(Data()) }
    }
}
