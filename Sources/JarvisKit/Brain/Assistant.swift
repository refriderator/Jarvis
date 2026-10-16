import Foundation

/// Answers a question the way Jarvis Private did: plain code for timers and new calendar events,
/// the local brain for small questions, Claude (or the chosen cloud brain) for big ones, Notion,
/// the camera, or when local is unsure.
@MainActor
public final class Assistant {
    /// Earlier turns newer than this are sent along so follow-ups make sense.
    public static let followUpWindow: TimeInterval = 5 * 60
    public static let maxFollowUpTurns = 3

    private let state: AppState
    private let makeLocal: @MainActor (Settings) -> ChatProvider?
    private let makeCloud: @MainActor (Settings) -> ChatProvider?
    private let tools: Toolbox
    private let log: TurnLog?

    /// The factories read settings and secrets at ask time, so changes apply to the next question.
    /// `log` records every question and model call raw, for training.
    public init(state: AppState,
                makeLocal: @escaping @MainActor (Settings) -> ChatProvider?,
                makeCloud: @escaping @MainActor (Settings) -> ChatProvider?,
                tools: Toolbox = .none, log: TurnLog? = nil) {
        self.state = state
        self.makeLocal = { settings in
            let local = makeLocal(settings)
            return log?.recording(local) ?? local
        }
        self.makeCloud = { settings in
            let cloud = makeCloud(settings)
            return log?.recording(cloud) ?? cloud
        }
        self.tools = tools
        self.log = log
    }

    /// A question held back by token saving until the user says yes or no.
    private struct WaitingForCloud {
        let cloud: ChatProvider
        let history: [ChatMessage]
        let note: String
        let needs: Toolbox.CloudNeeds
    }
    private var waiting: WaitingForCloud?
    /// An app Jarvis offered to open for a change it can't make, until the person answers (or the follow-up window ends).
    private var offered: (app: String, at: Date)?

    private static let yes = try! NSRegularExpression(
        pattern: #"^\W*(yes|yeah|yep|yup|sure|ok|okay|please|do it|go ahead|open it)\b"#, options: .caseInsensitive)
    private static let no = try! NSRegularExpression(
        pattern: #"^\W*(no|nope|nah|don'?t|never ?mind|cancel|skip)\b"#, options: .caseInsensitive)

    public func ask(_ text: String, spoken: Bool = false) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, state.turns.last?.isPending != true else { return }
        if waiting != nil { skipCloud() }
        let history = followUps()
        state.beginTurn(question, spoken: spoken)
        log?.begin(question, spoken: spoken)
        Task { await answer(question, after: history) }
    }

    /// Token saving: the user said yes, so ask the cloud brain.
    public func useCloud() {
        guard let waiting else { return }
        self.waiting = nil
        state.setAwaitingCloud(false)
        Task { await askCloud(waiting.cloud, history: waiting.history, note: waiting.note, needs: waiting.needs) }
    }

    /// Token saving: the user said no.
    public func skipCloud() {
        guard waiting != nil else { return }
        waiting = nil
        fail("Skipped, no cloud tokens used.")
    }

    private func answer(_ asked: String, after earlier: [ChatMessage]) async {
        // "Hey Jarvis, ..." (or whatever it's called): the name isn't part of the question.
        let text = AssistantName.dropAddress(asked, name: state.settings.assistantName)
        if let offer = offered {
            offered = nil
            let range = NSRange(text.startIndex..., in: text)
            if Date.now.timeIntervalSince(offer.at) < Self.followUpWindow {
                if Self.yes.firstMatch(in: text, range: range) != nil {
                    finish(tools.openApp(offer.app).map { "Opening \($0)." } ?? "I couldn't open \(offer.app).", source: "Apps", tokens: 0)
                    return
                }
                if Self.no.firstMatch(in: text, range: range) != nil {
                    finish("Okay.", source: "Apps", tokens: 0)
                    return
                }
            }
        }
        if let ask = MorningBrief.ask(text), let brief = await brief(ask) {
            finish(brief, source: ask == .morning ? "Morning" : "Weather", tokens: 0)
            return
        }
        var local = makeLocal(state.settings)
        // Calendar adds are plain code: the local brain can only read, and the cloud brain can't reach the calendar.
        if let instant = tools.instantReply(text) {
            finish(instant.text, source: instant.source, tokens: 0)
            return
        }
        let needs = tools.needs(text)
        // Photos need the cloud; Notion needs a local model that can use tools.
        if needs.photo || (needs.notion && local?.canUseTools != true) { local = nil }
        let decision = Router.decide(text, localAvailable: local != nil, preferLocal: state.settings.localFirst,
                                     hasTools: needs.notion || tools.isScheduling(text))
        let question = ChatMessage(.user, Persona.context() + tools.context(for: text) + decision.question)
        var note = ""

        if decision.route == .local, let local {
            do {
                let reply = try await askLocal(local, text: text, history: earlier + [question], needs: needs)
                if !Router.isEscalation(reply.text) {
                    // Free and on this Mac, so it doesn't count toward the token meter.
                    finish(reply.text, source: local.label, tokens: 0)
                    return
                }
                note = " · local unsure"
            } catch {
                note = " · local failed"
            }
        }
        // With Claude's access on, the cloud brain has the timers and calendar itself.
        let access = state.settings.claudeAccess
        if access == .none, let hint = tools.cloudCantDo(text) {
            fail(hint)
            return
        }
        // The local brain is on but can't make this change: say so and offer the app, instead of guessing or
        // sending it to a cloud brain that can't reach the calendar.
        if local != nil, !decision.namedClaude, access == .none, let app = tools.openOffer(for: text) {
            offered = (app, .now)
            finish(Toolbox.offerText(app: app), source: "Apps", tokens: 0)
            return
        }
        guard let cloud = makeCloud(state.settings) else {
            fail("No cloud brain is set up. Choose one in Settings › Connections.")
            return
        }
        if needs.any && !cloud.supportsExtras {
            fail("\(cloud.label) can't use Notion or the camera. Pick Claude Code or a Claude API key in Settings › Connections.")
            return
        }
        if state.settings.askBeforeCloud && !decision.namedClaude {
            waiting = WaitingForCloud(cloud: cloud, history: earlier + [question], note: note, needs: needs)
            state.setAwaitingCloud(true, source: cloud.label + note)
            return
        }
        await askCloud(cloud, history: earlier + [question], note: note, needs: needs)
    }

    /// The morning brief, or just the weather. Nil when there's no weather to give, so a brain answers instead.
    private func brief(_ ask: MorningBrief.Ask, now: Date = .now) async -> String? {
        guard let source = tools.weather else { return nil }
        let city = state.settings.weatherCity.trimmingCharacters(in: .whitespaces)
        let report = try? await source.current(city: city.isEmpty ? nil : city)
        if ask == .weather { return report.map(MorningBrief.weather) }
        let day = Calendar.current.dateInterval(of: .day, for: now)
        let events = day.flatMap { tools.calendar?.events(from: $0.start, to: $0.end) }
        return MorningBrief.text(now: now, weather: report, events: events ?? [], due: state.due, calendarOn: events != nil)
    }

    /// Plain reply, or the tool loop when the request needs tools and the model can use them.
    private func askLocal(_ local: ChatProvider, text: String, history: [ChatMessage],
                          needs: Toolbox.CloudNeeds) async throws -> ChatReply {
        let kits = local.canUseTools ? try tools.localKits(for: text, needs: needs) : []
        if kits.isEmpty { return try await local.reply(system: Persona.local, history: history) }
        return try await LocalToolLoop.run(local, history: history, kits: kits, hint: tools.localHint(for: text, kits: kits, needs: needs))
    }

    private func askCloud(_ cloud: ChatProvider, history: [ChatMessage], note: String, needs: Toolbox.CloudNeeds) async {
        do {
            // The photo is taken only now, after any token-saving check said yes.
            var extras = try await tools.extras(for: needs, access: state.settings.claudeAccess)
            // Only Claude can use them; other cloud brains get the question alone.
            if !cloud.supportsExtras { extras = .none }
            let reply = try await cloud.reply(system: Persona.cloud(name: AssistantName.display(state.settings.assistantName)), history: history, extras: extras)
            finish(reply.text, source: cloud.label + note, tokens: reply.totalTokens, cloud: true)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// The caption's Summarize button: the cloud brain turns the last answer into points (see `Summary`).
    /// Clicked on purpose, so token saving doesn't ask first.
    public func summarize() {
        guard let turn = state.turns.last, turn.cloud, let answer = turn.answer, turn.summary == nil,
              !turn.summarizing, let cloud = makeCloud(state.settings) else { return }
        state.beginSummary()
        let text = turn.question.isEmpty ? answer : "Question: \(turn.question)\n\nAnswer: \(answer)"
        Task {
            let reply = try? await cloud.reply(system: Summary.prompt, history: [ChatMessage(.user, text)])
            state.finishSummary(reply.flatMap { Summary.parse($0.text) }, tokens: reply?.totalTokens ?? 0)
        }
    }

    private func finish(_ text: String, source: String, tokens: Int, cloud: Bool = false) {
        state.finishTurn(text, source: source, tokens: tokens, cloud: cloud)
        log?.finish(answer: text, source: source)
    }

    private func fail(_ reason: String) {
        state.failTurn(reason)
        log?.finish(answer: nil, source: nil, failure: reason)
    }

    /// Recent answered turns as chat history, oldest first.
    private func followUps(now: Date = .now) -> [ChatMessage] {
        state.turns
            .filter { !$0.failed && !$0.question.isEmpty && $0.answer != nil
                && now.timeIntervalSince($0.asked) < Self.followUpWindow }
            .suffix(Self.maxFollowUpTurns)
            .flatMap { [ChatMessage(.user, $0.question), ChatMessage(.assistant, $0.answer ?? "")] }
    }
}
