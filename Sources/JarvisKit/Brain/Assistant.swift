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
        var local = makeLocal(state.settings)
        let localDoesTools = state.settings.localFirst && local?.canUseTools == true
        if let instant = tools.instantReply(text, calendar: !localDoesTools) {
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
        if let hint = tools.cloudCantDo(text) {
            fail(hint)
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
            let extras = try await tools.extras(for: needs)
            let reply = try await cloud.reply(system: Persona.cloud(name: AssistantName.display(state.settings.assistantName)), history: history, extras: extras)
            finish(reply.text, source: cloud.label + note, tokens: reply.totalTokens)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func finish(_ text: String, source: String, tokens: Int) {
        state.finishTurn(text, source: source, tokens: tokens)
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
