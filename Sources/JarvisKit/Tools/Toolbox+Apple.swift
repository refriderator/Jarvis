import Foundation

/// The jobs handed to Apple's own apps, read by code before any brain: reminders (Reminders app), alarms (Clock app,
/// through the "Jarvis Alarm" shortcut) and running a shortcut by name. Kept out of every model on purpose: a small
/// model got dates wrong, and no cloud brain can reach these apps.
extension Toolbox {
    /// A finished reply, or nil to let a brain answer.
    public func appleReply(_ text: String, now: Date = .now) async -> (text: String, source: String)? {
        if let shortcuts, let said = ShortcutCommand.name(in: text) {
            guard let name = ShortcutCommand.match(said, in: await shortcuts.names()) else {
                return ("You don't have a shortcut called \(said).", "Shortcuts")
            }
            do {
                let output = try await shortcuts.run(name, input: nil)
                return (output.isEmpty ? "Ran \(name)." : output, "Shortcuts")
            } catch {
                return (error.localizedDescription, "Shortcuts")
            }
        }
        if let alarm = AlarmCommand.parse(text) {
            return (await setAlarm(alarm, now: now), "Alarm")
        }
        if let reminders, let command = ReminderCommand.parse(text) {
            guard case .add(let title, let when) = command else { return (ReminderCommand.unclearReply, "Reminders") }
            let due = when?.resolve(now: now)
            do {
                try reminders.add(title: title, due: due?.date, hasTime: due?.hasTime ?? false)
                return (ReminderCommand.confirmation(title: title, due: due, now: now), "Reminders")
            } catch {
                return (error.localizedDescription, "Reminders")
            }
        }
        return nil
    }

    private func setAlarm(_ command: AlarmCommand, now: Date) async -> String {
        switch command {
        case .off: return AlarmCommand.offReply
        case .unclear: return AlarmCommand.unclearReply
        case .set(let time):
            guard let when = time.resolve(now: now) else { return AlarmCommand.unclearReply }
            guard let shortcuts, await shortcuts.names().contains(AlarmCommand.shortcutName) else {
                return AlarmCommand.needsShortcut
            }
            do {
                // A date the shortcut's "Get Dates from Input" reads in any region: "October 18, 2026 at 7:00 AM".
                _ = try await shortcuts.run(AlarmCommand.shortcutName,
                                            input: when.date.formatted(date: .long, time: .shortened))
            } catch {
                return error.localizedDescription
            }
            let day = Calendar.current.isDate(when.date, inSameDayAs: now) ? "" : " tomorrow"
            return "Alarm set for \(when.date.formatted(date: .omitted, time: .shortened))\(day)."
        }
    }
}
