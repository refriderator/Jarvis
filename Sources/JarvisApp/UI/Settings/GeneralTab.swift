import JarvisKit
import SwiftUI

struct GeneralTab: View {
    let state: AppState

    var body: some View {
        Form {
            Section("Name") {
                NameField(state: state)
            }
            Section {
                Toggle("Launch at login", isOn: state.binding(\.launchAtLogin))
                Toggle("Show in menu bar", isOn: state.binding(\.showInMenuBar))
                Toggle("Quick Dock", isOn: state.binding(\.quickDock))
                    .help("One window at a time: the app you switch to fills the desktop, and the rest wait on the sides")
                Picker("Open the notch on", selection: state.binding(\.openTrigger)) {
                    Text("Click (hover peeks)").tag(OpenTrigger.click)
                    Text("Hover").tag(OpenTrigger.hover)
                }
                if !state.settings.showInMenuBar {
                    Text("With the icon hidden, open Jarvis again from Applications to get back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                HotkeyRecorder(label: "Talk", hotkey: state.binding(\.talkHotkey), fallback: .talk)
                HotkeyRecorder(label: "Type", hotkey: state.binding(\.typeHotkey), fallback: .type)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Work from any app. While Jarvis talks, \(Hotkey.stop.text) stops it. Hold or press Talk: see the Voice tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Hold windows in the notch", isOn: state.binding(\.holdWindows))
                if state.settings.holdWindows && !AccessibilityAccess.isTrusted {
                    Button("Allow Accessibility…", action: AccessibilityAccess.request)
                }
                if !CGPreflightScreenCaptureAccess() {
                    Button("Allow Screen Recording for live previews…") { _ = CGRequestScreenCaptureAccess() }
                }
            } header: {
                Text("Windows")
            } footer: {
                Text("Drag a window by its title bar onto the notch to hold it. It waits just off the nearer side of the screen (drag a window to the left or right edge to put it there); point at that edge to see it, and click it to use it from the side. Needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
