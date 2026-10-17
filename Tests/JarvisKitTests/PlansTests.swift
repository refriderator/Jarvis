import Foundation
@testable import JarvisKit
import Testing

/// Plans questions see the calendar and Notion for the days asked about, whatever the wording.
@MainActor
struct PlansTests {
    /// Saturday, October 17, 2026, 9 AM.
    private let saturday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9))!

    private func day(_ date: Date) -> DateComponents { Calendar.current.dateComponents([.month, .day], from: date) }

    @Test func readsTheDaysAskedAbout() {
        let tuesday = CalendarCommand.range(for: "what's on tuesday", now: saturday)
        #expect(day(tuesday.start) == DateComponents(month: 10, day: 20))
        #expect(tuesday.end.timeIntervalSince(tuesday.start) == 86_400, "just that day")
        #expect(day(CalendarCommand.range(for: "anything on saturday", now: saturday).start) == DateComponents(month: 10, day: 17),
                "today, when today is that day")
        let weekend = CalendarCommand.range(for: "my plans this weekend", now: saturday)
        #expect(day(weekend.start) == DateComponents(month: 10, day: 17))
        #expect(day(weekend.end) == DateComponents(month: 10, day: 19))
        #expect(day(CalendarCommand.range(for: "what's on tomorrow", now: saturday).start) == DateComponents(month: 10, day: 17),
                "no day named: today and tomorrow, as before")
    }

    @Test func knowsAPlansQuestionHoweverWorded() {
        let tools = Toolbox()
        for text in ["what's on tuesday", "what's due tuesday", "am I free friday", "when's my next exam",
                     "what do I have this week", "my plans this weekend"] {
            #expect(tools.isPlans(text), "\(text)")
        }
        for text in ["explain how a transistor works", "write an email to my TA", "plan a trip to japan",
                     "add dentist to my calendar friday at 3pm"] {
            #expect(!tools.isPlans(text), "\(text)")
        }
    }

    @Test func notesWhatsDueInNotion() {
        let item = DueItem(id: "1", title: "PHY224 Midterm", due: saturday.addingTimeInterval(3 * 86_400), hasTime: false,
                           source: "Exams")
        let start = Calendar.current.startOfDay(for: saturday).addingTimeInterval(3 * 86_400)
        let note = Toolbox.dueNote([item], start: start, end: start.addingTimeInterval(86_400), now: saturday)
        #expect(note.contains("PHY224 Midterm"))
        #expect(Toolbox.dueNote([], start: start, end: start.addingTimeInterval(86_400), now: saturday).contains("Nothing is due"))
    }

    @Test func tuesdaysEventsReachTheBrain() async {
        let state = AppState()
        let calendar = FakeCalendar()
        let next = CalendarCommand.range(for: "tuesday").start.addingTimeInterval(10 * 3600)
        _ = try? calendar.add(title: "Study group", start: next, end: next.addingTimeInterval(3600), allDay: false)
        let cloud = FakeBrain("Claude", answer: "Study group at 10.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud },
                                  tools: Toolbox(calendar: calendar))
        assistant.ask("what's on tuesday")
        for _ in 0..<200 where state.turns.last?.isPending == true { await Task.yield() }
        #expect(cloud.asked.first?.last?.text.contains("Study group") == true)
    }
}
