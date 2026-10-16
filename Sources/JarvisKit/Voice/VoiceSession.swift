import Foundation

/// Talk and type shortcuts, listening, and reading answers aloud.
/// Push-to-hold listens while the talk key is down; toggle listens until it is pressed again.
@MainActor
public final class VoiceSession {
    private let state: AppState
    private let assistant: Assistant
    private let listener: Listener
    private let speaker: Speaker
    private let hotkeys: Hotkeys
    private var spokenTurn: UUID?
    private var endOfSpeech: EndOfSpeech?
    private var pauseWatcher: Task<Void, Never>?

    public init(state: AppState, assistant: Assistant, listener: Listener, speaker: Speaker, hotkeys: Hotkeys) {
        self.state = state
        self.assistant = assistant
        self.listener = listener
        self.speaker = speaker
        self.hotkeys = hotkeys
        speaker.onFinish = { [weak self] in self?.finishedSpeaking() }
    }

    public func start() {
        observeShortcuts()
        observeAnswers()
    }

    // MARK: Talking

    public func talkPressed() {
        switch state.settings.talkMode {
        case .pushToHold: beginListening(watchForPause: false)
        case .toggle: toggleTalk()
        }
    }

    public func talkReleased() {
        if state.settings.talkMode == .pushToHold { endListening() }
    }

    /// The mic button and the menu's Talk item.
    public func toggleTalk() {
        state.voice.isListening ? endListening() : beginListening()
    }

    public func stopSpeaking() {
        speaker.stop()
    }

    /// `watchForPause`: stop on its own when the user stops talking (not while a key is held down).
    private func beginListening(watchForPause: Bool = true) {
        guard !state.voice.isListening else { return }
        speaker.stop()
        let missing = [Permission.microphone, .speech].filter { state.permissions.status($0) != .granted }
        guard missing.isEmpty else {
            // Ask now; the user presses talk again once allowed (a prompt mid-hold would swallow the release).
            Task {
                for permission in missing where await state.permissions.request(permission) != .granted {
                    state.send(.summon)
                    state.announce("Jarvis needs \(permission.title) access to hear you. Allow it in System Settings › "
                                   + "Privacy & Security.", source: "Voice", failed: true)
                    return
                }
            }
            return
        }
        state.send(.summon)
        state.setVoice(.listening(""))
        let pause = state.settings.pauseToSend
        endOfSpeech = watchForPause && pause > 0 ? EndOfSpeech(pause: pause) : nil
        do {
            try listener.start(microphoneID: state.settings.micDeviceID) { [weak self] text in
                guard let self, state.voice.isListening else { return }
                endOfSpeech?.heard(text)
                state.setVoice(.listening(text))
            }
            watchForPauses()
        } catch {
            state.setVoice(.idle)
            state.announce(error.localizedDescription, source: "Voice", failed: true)
        }
    }

    /// Checks a few times a second whether the user has gone quiet.
    private func watchForPauses() {
        pauseWatcher?.cancel()
        guard endOfSpeech != nil else { return }
        pauseWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, state.voice.isListening else { return }
                if endOfSpeech?.shouldStop() == true {
                    endListening()
                    return
                }
            }
        }
    }

    private func endListening() {
        guard state.voice.isListening else { return }
        pauseWatcher?.cancel()
        endOfSpeech = nil
        Task {
            let text = await listener.finish()
            state.setVoice(.idle)
            if text.isEmpty {
                // Heard nothing: the caption has nothing to show, so go back to the list.
                state.endCaption()
            } else {
                assistant.ask(text, spoken: true)
            }
        }
    }

    // MARK: Speaking

    private func observeAnswers() {
        withObservationTracking {
            _ = state.turns.last?.answer
            _ = state.turns.last?.awaitingCloud
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.speakLatest()
                self?.observeAnswers()
            }
        }
    }

    private func speakLatest() {
        guard let turn = state.turns.last, turn.spoken, !turn.awaitingCloud, let answer = turn.answer,
              turn.id != spokenTurn, !state.voice.isListening else { return }
        spokenTurn = turn.id
        state.setVoice(.speaking)
        // Esc (or the chosen stop key) is only taken while Jarvis talks, so it never steals the key otherwise.
        hotkeys.register(.stop, .stop) { [weak self] in self?.stopSpeaking() }
        speaker.speak(answer, voiceID: state.settings.voiceID, rate: state.settings.speechRate)
    }

    private func finishedSpeaking() {
        hotkeys.unregister(.stop)
        if state.voice == .speaking { state.setVoice(.idle) }
    }

    // MARK: Shortcuts

    private func observeShortcuts() {
        let talk = state.settings.talkHotkey
        let type = state.settings.typeHotkey
        hotkeys.register(.talk, talk, press: { [weak self] in self?.talkPressed() },
                         release: { [weak self] in self?.talkReleased() })
        hotkeys.register(.type, type) { [weak self] in self?.state.send(.summon) }
        withObservationTracking {
            _ = state.settings.talkHotkey
            _ = state.settings.typeHotkey
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcuts() }
        }
    }
}
