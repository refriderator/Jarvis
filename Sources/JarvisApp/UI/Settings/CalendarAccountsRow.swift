import AppKit
import JarvisKit
import SwiftUI

/// Which calendars Jarvis can see, and a shortcut to add Google (or any account) to Calendar.app.
struct CalendarAccountsRow: View {
    @State private var accounts: [String] = []

    var body: some View {
        LabeledContent {
            Button("Add Google Calendar…") { NSWorkspace.shared.open(EventKitCalendar.addAccountURL) }
        } label: {
            Text("Calendars")
            Text(accounts.isEmpty
                 ? "Uses Apple Calendar, which includes any Google, iCloud or Exchange calendars added to it."
                 : accounts.joined(separator: "\n"))
        }
        Text("Google: System Settings › Internet Accounts › Add Account › Google, sign in, and turn on Calendars. "
             + "It then shows up in Calendar.app and Jarvis can read and add events, no extra sign-in.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .onAppear { accounts = EventKitCalendar.accounts() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accounts = EventKitCalendar.accounts()
            }
    }
}
