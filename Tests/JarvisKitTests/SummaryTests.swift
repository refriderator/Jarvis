import Foundation
import JarvisKit
import Testing

@MainActor
struct SummaryTests {
    @Test func parsesJSONInsideFencesAndProse() throws {
        let reply = """
            Here you go:
            ```json
            {"points": [{"symbol": "bolt.fill", "text": "**Current** follows $V/R$"}], "formula": "V = IR",
             "bars": [{"label": "Cu", "value": 1.7}, {"label": "Al", "value": 2.8}], "unit": "nΩ·m"}
            ```
            """
        let summary = try #require(Summary.parse(reply))
        #expect(summary.points == [Summary.Point(symbol: "bolt.fill", text: "Current follows V/R")])
        #expect(summary.formula == "V = IR")
        #expect(summary.bars.count == 2)
        #expect(summary.unit == "nΩ·m")
    }

    @Test func emptyFieldsBecomeNothing() throws {
        let summary = try #require(Summary.parse(#"{"points": [{"text": "One"}], "formula": "", "bars": [{"label": "a", "value": 1}], "unit": ""}"#))
        #expect(summary.formula == nil)
        #expect(summary.bars.isEmpty)
        #expect(summary.unit == nil)
    }

    @Test func noPointsOrNoJSONIsNoSummary() {
        #expect(Summary.parse("Sorry, I can't.") == nil)
        #expect(Summary.parse(#"{"points": []}"#) == nil)
    }

    @Test func summaryPullsTheCaptionDownAndSwitchesBack() throws {
        let state = AppState()
        state.beginTurn("Why is the sky blue?")
        state.finishTurn("Rayleigh scattering.", source: "Claude", tokens: 10, cloud: true)
        let answerHeight = state.layout.captionHeight
        state.beginSummary()
        #expect(state.captionPinned)
        let points = (1...4).map { Summary.Point(symbol: nil, text: "Point \($0)") }
        state.finishSummary(Summary(points: points, formula: "I ∝ 1/λ⁴", bars: [], unit: nil), tokens: 5)
        #expect(state.showsSummary)
        #expect(state.layout.captionHeight > answerHeight)
        #expect(state.turns.last?.tokens == 15)
        state.toggleSummary()
        #expect(!state.showsSummary)
        #expect(state.layout.captionHeight < NotchLayout.summaryHeight(for: try #require(state.turns.last?.summary)))
    }

    @Test func failedSummaryShowsTheAnswerAgain() {
        let state = AppState()
        state.beginTurn("Hi")
        state.finishTurn("Hello.", source: "Claude", tokens: 0, cloud: true)
        state.beginSummary()
        state.finishSummary(nil, tokens: 0)
        #expect(!state.showsSummary)
        #expect(state.turns.last?.summarizing == false)
    }
}
