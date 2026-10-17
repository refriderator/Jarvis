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
                Toggle("Window previews on the side cards", isOn: state.binding(\.windowPreviews))
                    .help("A live picture of each held window; off, its app's icon and title")
                if state.settings.windowPreviews && !CGPreflightScreenCaptureAccess() {
                    Button("Allow Screen Recording for the previews…") { _ = CGRequestScreenCaptureAccess() }
                }
            } header: {
                Text("Windows")
            } footer: {
                Text("Drag a window by its title bar onto the notch, or to the left or right edge, to hold it there. Point at the edge to see it; click it to use it. Drag it by its title bar into the middle to let it go. Needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            UpdateSection()
        }
    }
}

private struct UpdateSection: View {
    @State private var error: String?

    var body: some View {
        Section {
            if let folder = Updater.sourceFolder {
                Button("Update Jarvis…") {
                    do { try Updater.openUpdate() } catch { self.error = error.localizedDescription }
                }
                .help("Gets the latest version from \(folder.path) and installs it")
            } else {
                Text("Can't find the folder Jarvis was installed from. Update from Terminal as the README says.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Uninstall Jarvis…", role: .destructive) {
                do { try Uninstaller.openUninstall() } catch { self.error = error.localizedDescription }
            }
            .help("Lists what would be removed and asks first")
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Update")
        } footer: {
            Text("Both open Terminal. Update downloads the latest version and rebuilds it (a few minutes); your settings are kept. Uninstall lists what it would remove (the app, settings, models, logs, saved keys) and asks before removing anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
