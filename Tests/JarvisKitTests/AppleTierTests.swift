import Foundation
@testable import JarvisKit
import Testing

/// Reminders, alarms, shortcuts, Siri links and text on screen: the jobs taken off the local brain.
struct SpokenTimeTests {
    private let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9, minute: 0))!

    @Test func readsTimes() {
        #expect(SpokenTime.parse("remind me in 20 minutes") == .after(seconds: 1200))
        #expect(SpokenTime.parse("at 8:45 pm") == .at(hour: 8, minute: 45, pm: true, tomorrow: false))
        #expect(SpokenTime.parse("at 7 in the morning") == .at(hour: 7, minute: 0, pm: false, tomorrow: false))
        #expect(SpokenTime.parse("tomorrow at 9") == .at(hour: 9, minute: 0, pm: nil, tomorrow: true))
        #expect(SpokenTime.parse("tomorrow") == .day(tomorrow: true))
        #expect(SpokenTime.parse("for 5 minutes") == nil, "a length without 'in' is no time")
        #expect(SpokenTime.parse("put clothes in the dryer") == nil)
    }

    @Test func resolvesToTheNextOne() {
        let at = { (time: SpokenTime) in Calendar.current.dateComponents([.day, .hour], from: time.resolve(now: morning)!.date) }
        #expect(at(.at(hour: 5, minute: 0, pm: nil, tomorrow: false)) == DateComponents(day: 17, hour: 17), "5 at 9 am: this evening")
        #expect(at(.at(hour: 7, minute: 0, pm: false, tomorrow: false)) == DateComponents(day: 18, hour: 7))
        #expect(at(.at(hour: 9, minute: 0, pm: nil, tomorrow: true)) == DateComponents(day: 18, hour: 9))
        #expect(SpokenTime.day(tomorrow: true).resolve(now: morning)?.hasTime == false)
    }
}

struct ReminderCommandTests {
    @Test func readsReminders() {
        #expect(ReminderCommand.parse("remind me in 20 minutes to call mom") == .add(title: "call mom", when: .after(seconds: 1200)))
        #expect(ReminderCommand.parse("remind me to take out the trash in an hour") == .add(title: "take out the trash", when: .after(seconds: 3600)))
        #expect(ReminderCommand.parse("remind me at 8:45 pm to call mom") == .add(title: "call mom", when: .at(hour: 8, minute: 45, pm: true, tomorrow: false)))
        #expect(ReminderCommand.parse("remind me to put clothes in the dryer at 5") == .add(title: "put clothes in the dryer", when: .at(hour: 5, minute: 0, pm: nil, tomorrow: false)))
        #expect(ReminderCommand.parse("remind me to call mom tomorrow") == .add(title: "call mom", when: .day(tomorrow: true)))
        #expect(ReminderCommand.parse("remind me to buy milk") == .add(title: "buy milk", when: nil))
        #expect(ReminderCommand.parse("set a reminder to water the plants at 6 pm") == .add(title: "water the plants", when: .at(hour: 6, minute: 0, pm: true, tomorrow: false)))
    }

    @Test func readsLooseWordings() {
        #expect(ReminderCommand.parse("can you set me a reminder for 8:20 to call mom") == .add(title: "call mom", when: .at(hour: 8, minute: 20, pm: nil, tomorrow: false)))
        #expect(ReminderCommand.parse("set a reminder for 8:20") == .unclear, "when, but not what")
        #expect(ReminderCommand.parse("reminder for 20 minutes") == .unclear)
        #expect(ReminderCommand.parse("i need a reminder to take my pills at 9 pm") == .add(title: "take my pills", when: .at(hour: 9, minute: 0, pm: true, tomorrow: false)))
    }

    @Test func readsOtherWordings() {
        #expect(ReminderCommand.parse("ping me at 9 to call mom") == .add(title: "call mom", when: .at(hour: 9, minute: 0, pm: nil, tomorrow: false)))
        #expect(ReminderCommand.parse("give me a heads up at 5 pm to leave") == .add(title: "leave", when: .at(hour: 5, minute: 0, pm: true, tomorrow: false)))
        #expect(ReminderCommand.parse("don't let me forget to pay rent") == .add(title: "pay rent", when: nil))
        #expect(ReminderCommand.parse("ping me in 10 min") == nil, "a timer")
        #expect(ReminderCommand.parse("tell me a joke") == nil)
        #expect(ReminderCommand.parse("let me know what's on tomorrow") == nil)
    }

    @Test func leavesTheRestAlone() {
        #expect(ReminderCommand.parse("remind me") == .unclear)
        #expect(ReminderCommand.parse("what are my reminders") == nil)
        #expect(ReminderCommand.parse("set a timer for 10 minutes") == nil)
    }

    @Test func confirms() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 9))!
        #expect(ReminderCommand.confirmation(title: "buy milk", due: nil, now: now) == "Added \"buy milk\" to Reminders.")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(ReminderCommand.confirmation(title: "call mom", due: (tomorrow, true), now: now).hasSuffix("tomorrow to call mom."))
    }
}

struct AlarmAndShortcutTests {
    @Test func readsAlarms() {
        #expect(AlarmCommand.parse("set an alarm for 7 am") == .set(.at(hour: 7, minute: 0, pm: false, tomorrow: false)))
        #expect(AlarmCommand.parse("wake me up at 6:30 tomorrow") == .set(.at(hour: 6, minute: 30, pm: nil, tomorrow: true)))
        #expect(AlarmCommand.parse("alarm in an hour") == .set(.after(seconds: 3600)))
        #expect(AlarmCommand.parse("cancel my alarm") == .off)
        #expect(AlarmCommand.parse("set an alarm") == .unclear)
        #expect(AlarmCommand.parse("what alarms do I have") == nil)
    }

    @Test func readsShortcutNames() {
        #expect(ShortcutCommand.name(in: "run my Focus shortcut") == "Focus")
        #expect(ShortcutCommand.name(in: "run the shortcut called Morning Routine") == "Morning Routine")
        #expect(ShortcutCommand.name(in: "open Safari") == nil)
        #expect(ShortcutCommand.match("morning routine", in: ["Morning Routine", "Focus"]) == "Morning Routine")
        #expect(ShortcutCommand.match("sleep", in: ["Focus"]) == nil)
    }

    @Test func readsSiriLinks() {
        #expect(SiriLink.question(in: URL(string: "jarvis://ask?q=what%27s%20on%20tomorrow")!) == "what's on tomorrow")
        #expect(SiriLink.question(in: URL(string: "jarvis://ask?q=")!) == nil)
        #expect(SiriLink.question(in: URL(string: "https://ask?q=hi")!) == nil)
    }
}

final class FakeShortcuts: ShortcutRunner, @unchecked Sendable {
    var installed: [String]
    var ran: [(name: String, input: String?)] = []

    init(_ installed: [String]) { self.installed = installed }

    func names() async -> [String] { installed }

    func run(_ name: String, input: String?) async throws -> String {
        ran.append((name, input))
        return ""
    }
}

@MainActor
final class FakeReminders: ReminderSource {
    var saved: [(title: String, due: Date?, hasTime: Bool)] = []

    func add(title: String, due: Date?, hasTime: Bool) throws { saved.append((title, due, hasTime)) }
}

@MainActor
final class FakeScreen: ScreenTextSource {
    var selected: String?
    var shown: ScreenPage?
    var copied: String?

    init(selected: String? = nil, page: ScreenPage? = nil) {
        self.selected = selected
        self.shown = page
    }

    func selection() -> String? { selected }

    func page() throws -> ScreenPage {
        guard let shown else { throw ChatError("There's no page in front to read.") }
        return shown
    }

    func copy(_ text: String) { copied = text }
}

@MainActor
struct AppleTierTests {
    private func run(_ assistant: Assistant, _ text: String, state: AppState) async {
        assistant.ask(text)
        for _ in 0..<200 where state.turns.last?.isPending == true { await Task.yield() }
    }

    @Test func remindersAndAlarmsNeverReachABrain() async {
        let state = AppState()
        let reminders = FakeReminders(), shortcuts = FakeShortcuts([AlarmCommand.shortcutName])
        let local = FakeBrain("Qwen", answer: "unused"), cloud = FakeBrain("Claude", answer: "unused")
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud },
                                  tools: Toolbox(timers: TimerCenter(state: state), reminders: reminders, shortcuts: shortcuts))
        await run(assistant, "remind me in 20 minutes to stretch", state: state)
        #expect(reminders.saved.first?.title == "stretch")
        #expect(state.turns.last?.source == "Reminders")
        #expect(state.turns.last.flatMap(Answerer.of)?.text == "Siri · Reminders")
        await run(assistant, "set an alarm for 7 am", state: state)
        #expect(shortcuts.ran.first?.name == AlarmCommand.shortcutName)
        #expect(state.turns.last?.answer?.hasPrefix("Alarm set for") == true)
        #expect(local.asked.isEmpty && cloud.asked.isEmpty)
        await run(assistant, "set a timer for 5 minutes", state: state)
        #expect(state.turns.last.flatMap(Answerer.of)?.text == "Jarvis · Timer")
    }

    @Test func anAlarmWithoutTheShortcutSaysHowToMakeIt() async {
        let state = AppState()
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in nil },
                                  tools: Toolbox(shortcuts: FakeShortcuts([])))
        await run(assistant, "wake me up at 6:30", state: state)
        #expect(state.turns.last?.answer == AlarmCommand.needsShortcut)
    }

    @Test func appleSummarizesThePageInFront() async {
        let state = AppState()
        let apple = FakeBrain("On-device", answer: "A page about robots.")
        let local = FakeBrain("Qwen", answer: "unused"), cloud = FakeBrain("Claude", answer: "unused")
        let screen = FakeScreen(page: ScreenPage(app: "Safari", title: "Robots", text: "Robots walk now."))
        let assistant = Assistant(state: state, makeLocal: { _ in local }, makeCloud: { _ in cloud },
                                  makeOnDevice: { apple }, tools: Toolbox(screen: screen))
        await run(assistant, "summarize this page", state: state)
        #expect(state.turns.last?.answer == "A page about robots.")
        #expect(state.turns.last?.source == Assistant.onDeviceSource)
        #expect(state.turns.last.flatMap(Answerer.of)?.text == "Apple Intelligence")
        #expect(local.asked.isEmpty && cloud.asked.isEmpty)
    }

    @Test func withoutAppleTheCloudSummarizes() async {
        let state = AppState()
        let cloud = FakeBrain("Claude", answer: "Robots, briefly.")
        let screen = FakeScreen(selected: "Robots walk now.")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud },
                                  makeOnDevice: { nil }, tools: Toolbox(screen: screen))
        await run(assistant, "summarize the selection", state: state)
        #expect(state.turns.last?.answer == "Robots, briefly.")
        #expect(cloud.asked.first?.last?.text.contains("Robots walk now.") == true)
        #expect(state.turns.last.flatMap(Answerer.of)?.text == "Claude · Apple Intelligence off")
    }

    @Test func aRewriteIsCopiedAndWithoutASelectionABrainAnswers() async {
        let state = AppState()
        let apple = FakeBrain("On-device", answer: "Dear team, thank you.")
        let cloud = FakeBrain("Claude", answer: "Sure.")
        let screen = FakeScreen(selected: "thx team")
        let assistant = Assistant(state: state, makeLocal: { _ in nil }, makeCloud: { _ in cloud },
                                  makeOnDevice: { apple }, tools: Toolbox(screen: screen))
        await run(assistant, "make this more formal", state: state)
        #expect(screen.copied == "Dear team, thank you.")
        screen.selected = nil
        await run(assistant, "make this more formal", state: state)
        #expect(state.turns.last?.source?.hasPrefix("Claude") == true)
    }

    @Test func textJobsAreReadFromTheWording() {
        #expect(TextJob.parse("summarize this page") == .summarize(.page))
        #expect(TextJob.parse("tldr") == .summarize(.either))
        #expect(TextJob.parse("summarize what I selected") == .summarize(.selection))
        #expect(TextJob.parse("summarize the french revolution") == nil, "a question, not text on screen")
        #expect(TextJob.parse("proofread the selection") == .rewrite(instruction: "proofread the selection"))
        #expect(TextJob.parse("make it shorter") == nil, "about the last answer")
    }

    @Test func longTextIsCutForTheOnDeviceModel() {
        let paragraph = String(repeating: "word ", count: 400)
        let parts = TextJob.parts(Array(repeating: paragraph, count: 10).joined(separator: "\n"))
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= TextJob.partChars })
    }
}
