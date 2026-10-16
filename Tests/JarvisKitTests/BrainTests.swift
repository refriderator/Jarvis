import Foundation
import JarvisKit
import Testing

struct RouterTests {
    @Test func smallQuestionsStayLocal() {
        #expect(Router.decide("what's the capital of France", localAvailable: true).route == .local)
    }

    @Test func notionWritingAndCodeGoToCloud() {
        for text in ["add this to my Notion to do", "write an email to my prof", "debug this code", "solve x^2 = 4",
                     "who won the most recent F1 race", "latest news on the election"] {
            #expect(Router.decide(text, localAvailable: true).route == .cloud, "\(text)")
        }
    }

    @Test func localFirstKeepsNotionChangesLocal() {
        // The local model decides: one change it makes itself, a big one it hands on with ESCALATE.
        #expect(Router.decide("add milk to my groceries list", localAvailable: true, preferLocal: true, hasTools: true).route == .local)
    }

    @Test func namingClaudeForcesCloudAndStripsTheName() {
        let decision = Router.decide("Claude, what is 2+2", localAvailable: true)
        #expect(decision == .init(route: .cloud, question: "what is 2+2", namedClaude: true))
        #expect(Router.decide("hey claude, hi", localAvailable: true).question == "hi")
    }

    @Test func longQuestionsGoToCloud() {
        let long = Array(repeating: "word", count: Router.longQuestionWords + 1).joined(separator: " ")
        #expect(Router.decide(long, localAvailable: true).route == .cloud)
    }

    @Test func noLocalBrainMeansCloud() {
        #expect(Router.decide("hi", localAvailable: false).route == .cloud)
    }

    @Test func spotsEscalation() {
        #expect(Router.isEscalation("ESCALATE"))
        #expect(Router.isEscalation("  escalate\n"))
        #expect(Router.isEscalation(""))
        #expect(Router.isEscalation("Canberra, I think. ESCALATE"))
        #expect(!Router.isEscalation("Paris."))
    }
}

struct ProviderParsingTests {
    @Test func claudeCodeResultCountsCachedInput() throws {
        let json = #"{"result":"Four.","is_error":false,"usage":{"input_tokens":2,"cache_creation_input_tokens":500,"cache_read_input_tokens":98,"output_tokens":5}}"#
        #expect(try ClaudeCodeProvider.parse(Data(json.utf8)) == ChatReply(text: "Four.", inputTokens: 600, outputTokens: 5))
    }

    @Test func claudeCodeErrorsAreReported() {
        let json = #"{"result":"Not logged in · Please run /login","is_error":true}"#
        #expect(throws: ChatError.self) { try ClaudeCodeProvider.parse(Data(json.utf8)) }
        #expect(throws: ChatError.self) { try ClaudeCodeProvider.parse(Data("garbage".utf8)) }
    }

    @Test func claudeAPIJoinsTextBlocksAndSkipsThinking() throws {
        let json = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hi "},{"type":"text","text":"there."}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":3}}"#
        #expect(try ClaudeAPIProvider.parse(Data(json.utf8), status: 200).reply.text == "Hi there.")
    }

    @Test func claudeAPIRefusalAndBadKey() {
        let refusal = #"{"content":[],"stop_reason":"refusal","usage":{"input_tokens":1,"output_tokens":0}}"#
        #expect(throws: ChatError.self) { try ClaudeAPIProvider.parse(Data(refusal.utf8), status: 200) }
        let bad = #"{"error":{"message":"invalid x-api-key"}}"#
        #expect(throws: ChatError("The Claude API key was rejected.")) { try ClaudeAPIProvider.parse(Data(bad.utf8), status: 401) }
    }

    @Test func openAICompatibleReply() throws {
        let json = #"{"choices":[{"message":{"content":"Yo."}}],"usage":{"prompt_tokens":7,"completion_tokens":2}}"#
        #expect(try OpenAICompatibleProvider.parse(Data(json.utf8)) == ChatReply(text: "Yo.", inputTokens: 7, outputTokens: 2))
    }
}

struct TokenMeterTests {
    @Test func countsReplySessionAndDay() {
        var meter = TokenMeter()
        meter.add(100)
        meter.add(50)
        #expect(meter.lastReply == 50)
        #expect(meter.session == 150)
        #expect(meter.today == 150)
    }

    @Test func newDayStartsTodayFromZero() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        var meter = TokenMeter(today: 999, day: Calendar.current.startOfDay(for: yesterday))
        meter.add(10)
        #expect(meter.today == 10)
    }

    @Test func fileStoreKeepsTodayAcrossLaunches() {
        let url = FileManager.default.temporaryDirectory.appending(path: "jarvis-\(UUID())/usage.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileUsageStore(url: url)
        var meter = store.load()
        meter.add(42)
        store.save(meter)
        let loaded = store.load()
        #expect(loaded.today == 42)
        #expect(loaded.session == 0, "session restarts each launch")
    }
}

@MainActor
final class FakeBrain: ChatProvider {
    let label: String
    var answer: String
    var fail = false
    var asked: [[ChatMessage]] = []

    init(_ label: String, answer: String) {
        self.label = label
        self.answer = answer
    }

    func reply(system: String, history: [ChatMessage]) async throws -> ChatReply {
        asked.append(history)
        if fail { throw ChatError("down") }
        return ChatReply(text: answer, inputTokens: 10, outputTokens: 5)
    }
}

@MainActor
struct AssistantTests {
    private func run(_ assistant: Assistant, _ text: String, state: AppState) async {
        assistant.ask(text)
        for _ in 0..<50 where state.turns.last?.isPending == true { await Task.yield() }
    }

    @Test func localAnswersSmallQuestions() async {
        let state = AppState()
        let local = FakeBrain("On-device", answer: "Paris.")
        let cloud = FakeBrain("Claude Code", answer: "unused")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud })
        await run(assistant, "capital of France?", state: state)
        #expect(state.turns.last?.answer == "Paris.")
        #expect(state.turns.last?.source == "On-device")
        #expect(cloud.asked.isEmpty)
        #expect(state.tokens.today == 0, "local answers are free, so not counted")
    }

    @Test func unsureLocalHandsOffToCloud() async {
        let state = AppState()
        let local = FakeBrain("On-device", answer: "ESCALATE")
        let cloud = FakeBrain("Claude Code", answer: "Deep answer.")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud })
        await run(assistant, "tell me a fun fact", state: state)
        #expect(state.turns.last?.answer == "Deep answer.")
        #expect(state.turns.last?.source == "Claude Code · local unsure")
    }

    @Test func bigQuestionsSkipLocal() async {
        let state = AppState()
        let local = FakeBrain("On-device", answer: "x")
        let cloud = FakeBrain("Claude Code", answer: "Done.")
        state.update { $0.localFirst = false }
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud })
        await run(assistant, "write an email to my prof", state: state)
        #expect(local.asked.isEmpty)
        #expect(state.turns.last?.source == "Claude Code")
    }

    @Test func followUpsCarryRecentTurns() async {
        let state = AppState()
        let cloud = FakeBrain("Claude", answer: "A.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud })
        await run(assistant, "first", state: state)
        await run(assistant, "second", state: state)
        let history = cloud.asked.last ?? []
        #expect(history.count == 3)
        #expect(history.first == ChatMessage(.user, "first"))
    }

    @Test func cloudFailureShowsAnError() async {
        let state = AppState()
        let cloud = FakeBrain("Claude", answer: "")
        cloud.fail = true
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud })
        await run(assistant, "hi", state: state)
        #expect(state.turns.last?.failed == true)
        #expect(state.turns.last?.answer == "down")
    }

    @Test func noCloudBrainExplainsWhatToDo() async {
        let state = AppState()
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in nil })
        await run(assistant, "hi", state: state)
        #expect(state.turns.last?.answer?.contains("Settings") == true)
    }

    @Test func tokenSavingWaitsForAYes() async {
        let state = AppState()
        state.update { $0.askBeforeCloud = true }
        let cloud = FakeBrain("Claude Code", answer: "Done.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud })
        await run(assistant, "hi", state: state)
        #expect(state.turns.last?.awaitingCloud == true)
        #expect(cloud.asked.isEmpty)

        assistant.useCloud()
        for _ in 0..<50 where state.turns.last?.answer == nil { await Task.yield() }
        #expect(state.turns.last?.answer == "Done.")
    }

    @Test func tokenSavingSkipUsesNoTokens() async {
        let state = AppState()
        state.update { $0.askBeforeCloud = true }
        let cloud = FakeBrain("Claude Code", answer: "Done.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud })
        await run(assistant, "hi", state: state)
        assistant.skipCloud()
        #expect(state.turns.last?.awaitingCloud == false)
        #expect(cloud.asked.isEmpty)
        #expect(state.tokens.today == 0)
    }

    @Test func tokenSavingTrustsNamingClaude() async {
        let state = AppState()
        state.update { $0.askBeforeCloud = true }
        let cloud = FakeBrain("Claude Code", answer: "Done.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud })
        await run(assistant, "Claude, hi", state: state)
        #expect(state.turns.last?.answer == "Done.")
    }
}

struct OllamaModelsTests {
    @Test func parsesInstalledModelNames() throws {
        let json = Data(#"{"models":[{"name":"qwen2.5-coder:14b","size":1},{"name":"gemma3:12b"}]}"#.utf8)
        #expect(try OllamaModels.parse(json) == ["gemma3:12b", "qwen2.5-coder:14b"])
    }
}

/// Runs a real model, so it only runs when `JARVIS_TEST_GGUF` points at a .gguf file.
struct LlamaEngineTests {
    @Test func stripsThinkingFromReplies() {
        #expect(LlamaEngine.clean("<think>hmm</think>\n\nParis.") == "Paris.")
        #expect(LlamaEngine.clean("<think>cut off mid-thought") == "")
        #expect(LlamaEngine.clean("  Paris. ") == "Paris.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"] != nil))
    func realModelAnswers() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["JARVIS_TEST_GGUF"])
        let engine = LlamaEngine()
        let result = try await engine.generate(modelPath: path, messages: [
            ("system", "Answer in one short sentence of plain text. /no_think"),
            ("user", "What is the capital of France?"),
        ])
        await engine.unload()
        print("MODEL SAID:", result.text, "| tokens in/out:", result.input, result.output)
        #expect(result.text.contains("Paris"))
        #expect(result.output > 0)
    }
}

struct ReadableTests {
    @Test func latexBecomesPlainMaths() {
        #expect(Readable.clean(#"The roots are $x = \pm\sqrt{2}$."#) == "The roots are x = ±√2.")
        #expect(Readable.clean(#"So $\frac{a+b}{2} \times 3$"#) == "So (a+b)/2 × 3")
        #expect(Readable.clean(#"Area is \(\pi r^2\)"#) == "Area is π r²")
        #expect(Readable.clean(#"$$E = mc^{2}$$"#) == "E = mc²")
        #expect(Readable.clean(#"$x_{1} \le 10^{-3}$"#) == "x₁ ≤ 10⁻³")
        #expect(Readable.clean(#"\frac{\sqrt{3}}{2}"#) == "√3/2")
    }

    @Test func markdownIsDropped() {
        #expect(Readable.clean("## Answer\n**Paris** is the `capital`.") == "Answer\nParis is the capital.")
        #expect(Readable.clean("It costs $5 and $10.") == "It costs $5 and $10.")
    }
}

@MainActor
struct TurnLogTests {
    private func lines(in folder: URL) throws -> [[String: Any]] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return try files.flatMap { file in
            try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map {
                try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
            }
        }
    }

    @Test func recordsEachCallAndTheTurn() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        let local = FakeBrain("On-device", answer: "ESCALATE")
        let cloud = FakeBrain("Claude Code", answer: "Deep answer.")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud },
                                  log: TurnLog(folder: folder) { true })
        assistant.ask("tell me a fun fact")
        for _ in 0..<50 where state.turns.last?.isPending == true { await Task.yield() }

        let logged = try lines(in: folder)
        #expect(logged.map { $0["type"] as? String } == ["call", "call", "turn"])
        #expect(logged.map { $0["brain"] as? String } == ["On-device", "Claude Code", nil])
        #expect(logged[0]["reply"] as? String == "ESCALATE", "the raw reply, escalation and all")
        let messages = try #require(logged[0]["messages"] as? [[String: String]])
        #expect(messages.first?["role"] == "system")
        #expect(messages.last?["content"]?.hasSuffix("tell me a fun fact") == true)
        #expect(logged[2]["question"] as? String == "tell me a fun fact")
        #expect(logged[2]["answer"] as? String == "Deep answer.")
        #expect(Set(logged.compactMap { $0["turn"] as? String }).count == 1, "one question, one turn id")
    }

    @Test func writesNothingWhenOff() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState()
        let local = FakeBrain("On-device", answer: "Paris.")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in nil },
                                  log: TurnLog(folder: folder) { false })
        assistant.ask("capital of France?")
        for _ in 0..<50 where state.turns.last?.isPending == true { await Task.yield() }
        #expect(try lines(in: folder).isEmpty)
        #expect(state.turns.last?.answer == "Paris.")
    }
}
