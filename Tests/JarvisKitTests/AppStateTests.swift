import CoreGraphics
import Foundation
import JarvisKit
import Testing

@MainActor
struct AppStateTests {
    @Test func updateSavesToStore() {
        let store = MemorySettingsStore()
        let state = AppState(store: store)
        state.update { $0.captionSize = .small }
        #expect(store.load().captionSize == .small)
    }

    @Test func loadsSavedSettingsOnStart() {
        var saved = Settings()
        saved.skinID = "terminal"
        saved.openTrigger = .hover
        let state = AppState(store: MemorySettingsStore(saved))
        #expect(state.skin.id == "terminal")
        #expect(state.notch.trigger == .hover)
    }

    @Test func openTriggerSettingReachesTheNotch() {
        let state = AppState()
        state.update { $0.openTrigger = .hover }
        state.send(.pointerEntered)
        #expect(state.notch.mode == .open)
    }

    @Test func secretsGoToTheSecretStoreNotSettings() {
        let store = MemorySettingsStore()
        let secrets = MemorySecretStore()
        let state = AppState(store: store, secrets: secrets)
        state.setSecret(.claudeAPIKey, "sk-test")
        #expect(secrets.get(.claudeAPIKey) == "sk-test")
        #expect(state.secret(.claudeAPIKey) == "sk-test")
        state.setSecret(.claudeAPIKey, "")
        #expect(state.secret(.claudeAPIKey) == nil)
    }
}

@MainActor
struct CaptionTests {
    @Test func questionStartsTheCaptionAndHidesTheList() {
        let state = AppState()
        state.updateLayout(NotchLayout(notch: CGRect(x: 0, y: 0, width: 200, height: 32)))
        state.setAgenda([AgendaItem(id: "1", title: "Lec", start: .now, end: .now.addingTimeInterval(3600), allDay: false)])
        let withList = state.layout.size(for: .open).height
        #expect(state.layout.agendaRows == 1)

        state.beginTurn("hi")
        #expect(state.captionActive)
        #expect(state.layout.showsCaption)
        #expect(state.layout.size(for: .open).height > withList, "the caption has more room than the list did")
        state.endCaption()
        #expect(!state.captionActive)
        #expect(state.layout.size(for: .open).height == withList)
    }

    @Test func listeningStartsTheCaptionAndMicOffEndsIt() {
        let state = AppState()
        state.setVoice(.listening("what's"))
        #expect(state.captionActive)
        #expect(!state.captionFinished)
        state.setVoice(.idle)
        state.endCaption()
        #expect(!state.captionActive)
    }

    @Test func finishedMeansAnsweredAndQuiet() {
        let state = AppState()
        state.beginTurn("hi", spoken: true)
        #expect(!state.captionFinished, "still thinking")
        state.finishTurn("Hello.", source: "Qwen", tokens: 0)
        #expect(state.captionFinished)
        state.setVoice(.speaking)
        #expect(!state.captionFinished, "still talking")
        state.setVoice(.idle)
        #expect(state.captionFinished)
        #expect(state.captionLinger == 2, "spoken answers only wait a beat")
    }

    @Test func waitingForAYesIsNotFinished() {
        let state = AppState()
        state.beginTurn("write an essay")
        state.setAwaitingCloud(true, source: "Claude Code")
        #expect(!state.captionFinished)
    }

    @Test func keepingTheCaptionGrowsItAndHoldsThePanel() {
        let state = AppState()
        state.beginTurn("explain")
        state.send(.summon)
        state.finishTurn(String(repeating: "word ", count: 80), source: "Claude", tokens: 0)
        let normal = state.layout.captionHeight
        state.toggleCaptionPin()
        #expect(state.captionPinned)
        #expect(state.layout.captionHeight > normal, "a kept caption shows the whole answer")
        state.send(.pointerExited)
        #expect(state.notch.mode == .open)
        state.toggleCaptionPin()
        #expect(state.layout.captionHeight == normal)
        state.send(.click(inside: false))
        #expect(state.notch.mode == .idle)
        state.endCaption()
        #expect(!state.captionPinned)
    }

    @Test func captionHeightGrowsWithTheAnswerUpToAMax() {
        #expect(NotchLayout.captionHeight(forAnswerLength: 20) == NotchLayout.defaultCaptionHeight)
        #expect(NotchLayout.captionHeight(forAnswerLength: 400) > NotchLayout.defaultCaptionHeight)
        #expect(NotchLayout.captionHeight(forAnswerLength: 100_000) == NotchLayout.maxCaptionHeight)
    }
}

struct EndOfSpeechTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func stopsAfterAPauseFollowingSpeech() {
        var detector = EndOfSpeech(pause: 1.3, now: start)
        detector.heard("what's", now: start.addingTimeInterval(1))
        detector.heard("what's on my", now: start.addingTimeInterval(1.6))
        #expect(!detector.shouldStop(now: start.addingTimeInterval(2.5)), "still within the pause")
        detector.heard("what's on my calendar", now: start.addingTimeInterval(2.8))
        #expect(!detector.shouldStop(now: start.addingTimeInterval(3.5)))
        #expect(detector.shouldStop(now: start.addingTimeInterval(4.2)), "1.4 s of quiet")
    }

    @Test func sameTextDoesNotCountAsSpeech() {
        var detector = EndOfSpeech(pause: 1, now: start)
        detector.heard("hello", now: start.addingTimeInterval(1))
        detector.heard("hello ", now: start.addingTimeInterval(1.9))
        #expect(detector.shouldStop(now: start.addingTimeInterval(2.1)), "a repeat of the same words isn't new speech")
    }

    @Test func givesUpWhenNothingIsSaid() {
        let detector = EndOfSpeech(pause: 1.3, waitForSpeech: 8, now: start)
        #expect(!detector.shouldStop(now: start.addingTimeInterval(7)))
        #expect(detector.shouldStop(now: start.addingTimeInterval(8)))
    }

    @Test func neverListensForever() {
        var detector = EndOfSpeech(pause: 1.3, longest: 30, now: start)
        for second in stride(from: 1.0, to: 40, by: 1) { detector.heard("word \(Int(second))", now: start.addingTimeInterval(second)) }
        #expect(detector.shouldStop(now: start.addingTimeInterval(30)))
    }
}

struct ReadableIdsTests {
    @Test func notionIdsAreNotSaid() {
        #expect(Readable.clean("MAT244 Online PS — due Thursday (Assignments, id 1f2e3d4c-aaaa-bbbb)") == "MAT244 Online PS — due Thursday (Assignments)")
        #expect(Readable.clean("[ ] Milk (block 9b8a7c)") == "[ ] Milk")
    }
}

@MainActor
struct LastResponseTests {
    @Test func offeredForAMinuteThenGone() {
        let state = AppState()
        #expect(state.lastResponse() == nil)
        state.beginTurn("hi")
        state.finishTurn("Hello.", source: "Qwen", tokens: 0)
        state.endCaption()
        #expect(state.lastResponse()?.answer == "Hello.")
        #expect(state.lastResponse(now: .now.addingTimeInterval(59)) != nil)
        #expect(state.lastResponse(now: .now.addingTimeInterval(61)) == nil)
    }

    @Test func notOfferedWhileItIsTheCaption() {
        let state = AppState()
        state.beginTurn("hi")
        state.finishTurn("Hello.", source: "Qwen", tokens: 0)
        #expect(state.captionActive)
        #expect(state.lastResponse() == nil)
    }

    @Test func clickingTheTabKeepsTheAnswerOnScreen() {
        let state = AppState()
        state.beginTurn("hi")
        state.finishTurn("Hello.", source: "Qwen", tokens: 0)
        state.endCaption()
        state.showLastResponse()
        #expect(state.captionActive)
        #expect(state.captionPinned)
        #expect(state.lastResponse() == nil)
    }
}
