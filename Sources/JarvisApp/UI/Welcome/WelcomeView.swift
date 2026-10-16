import JarvisKit
import SwiftUI

/// First run, in three parts: meet it (what it does, and what to call it), set up (permissions, look, voice,
/// brains: the essentials only), and a few tips to start with. Everything is skippable and can be changed later in
/// Settings; the Features tab there explains the rest.
struct WelcomeView: View {
    let state: AppState
    let downloader: ModelDownloader
    let finish: () -> Void
    @State private var step = Step.meet

    enum Step: Int, CaseIterable {
        case meet, permissions, look, voice, brains, start

        /// Which of the three parts it belongs to, and its place among the setup steps.
        var part: (number: Int, title: String, detail: String?) {
            switch self {
            case .meet: (1, "Meet your assistant", nil)
            case .permissions: (2, "Set up", "Permissions · 1 of 4")
            case .look: (2, "Set up", "Look and feel · 2 of 4")
            case .voice: (2, "Set up", "Voice · 3 of 4")
            case .brains: (2, "Set up", "Who answers · 4 of 4")
            case .start: (3, "You're set", nil)
            }
        }
    }

    private var name: String { AssistantName.display(state.settings.assistantName) }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if step != .meet {
                    Button("Back") { move(-1) }
                }
                Spacer()
                StepDots(count: Step.allCases.count, current: step.rawValue)
                Spacer()
                Button(step == .start ? "Start" : "Continue") { move(1) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 540)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Step \(step.part.number) of 3").font(.caption.weight(.semibold)).foregroundStyle(state.skin.accent)
            Text(step.part.title).font(.headline)
            if let detail = step.part.detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .meet:
            MeetStep(state: state)
        case .permissions:
            Form {
                Section {
                    ForEach(Permission.allCases) { permission in
                        PermissionRow(state: state, permission: permission)
                    }
                } footer: {
                    note("\(name) asks only for what it uses. Skip any of them; it just won't do that part.")
                }
            }
            .formStyle(.grouped)
        case .look:
            Form {
                Section("Skin") {
                    Picker("Skin", selection: state.binding(\.skinID)) {
                        ForEach(SkinCatalog.all) { skin in Text(skin.name).tag(skin.id) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Section {
                    Picker("Open the notch on", selection: state.binding(\.openTrigger)) {
                        Text("Click (hover peeks)").tag(OpenTrigger.click)
                        Text("Hover").tag(OpenTrigger.hover)
                    }
                    Toggle("Launch at login", isOn: state.binding(\.launchAtLogin))
                } footer: {
                    note("Try it now: the notch at the top of your screen already follows these.")
                }
            }
            .formStyle(.grouped)
        case .voice:
            VoiceTab(state: state).formStyle(.grouped)
        case .brains:
            ConnectionsTab(state: state, downloader: downloader, compact: true).formStyle(.grouped)
        case .start:
            StartStep(state: state, name: name)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func move(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else {
            state.update { $0.hasCompletedWelcome = true }
            finish()
            return
        }
        step = next
    }
}

/// Step 1: what it does at a glance, and what to call it.
private struct MeetStep: View {
    let state: AppState

    private static let highlights: [(icon: String, title: String, text: String)] = [
        ("waveform", "Talk or type", "Ask anything; answers are spoken and captioned."),
        ("calendar", "Today", "Your events, what's due, timers. Say \u{201C}good morning\u{201D}."),
        ("folder", "Finder", "A folder in the notch: drop files in, drag them out."),
        ("globe", "Web", "A small browser with tabs and bookmarks."),
        ("rectangle.on.rectangle", "Hold windows", "Drag a window to the notch or a screen edge to set it aside."),
        ("pip", "Video", "Keep a Picture in Picture video in the notch."),
    ]

    var body: some View {
        let name = AssistantName.display(state.settings.assistantName)
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(state.skin.accent)
                Text("Hi, I'm \(name)").font(.largeTitle.bold())
                Text("I live in your notch. Quick jobs are done on this Mac for free; questions go to an AI you choose.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 12) {
                    ForEach(Self.highlights, id: \.title) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.icon)
                                .frame(width: 22)
                                .foregroundStyle(state.skin.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.callout.weight(.semibold))
                                Text(item.text).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
                NameField(state: state)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
    }
}

/// What to call it, with what might go wrong with that name.
struct NameField: View {
    let state: AppState

    var body: some View {
        let warnings = AssistantName.warnings(for: state.settings.assistantName)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Call me").font(.callout.weight(.semibold))
                TextField(AssistantName.standard, text: state.binding(\.assistantName))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            if warnings.isEmpty {
                Text("Pick any name; it's what I call myself and what the notch shows. Saying it before a question "
                     + "(\u{201C}Hey \(AssistantName.display(state.settings.assistantName)), …\u{201D}) is fine.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Step 3: the few things to know to start, and where the rest is explained.
private struct StartStep: View {
    let state: AppState
    let name: String

    var body: some View {
        let opens = state.settings.openTrigger == .hover ? "Hover over the notch" : "Click the notch"
        VStack(alignment: .leading, spacing: 14) {
            tip("cursorarrow.click", "\(opens) to open \(name).", "Type in the field at the bottom, or press the mic.")
            tip("keyboard", "\(state.settings.talkHotkey.text) to talk, \(state.settings.typeHotkey.text) to type, from any app.",
                "Esc stops \(name) talking. Shortcuts are in Settings › General.")
            tip("text.bubble", "Try \u{201C}good morning\u{201D}, \u{201C}set a timer for 10 minutes\u{201D} or \u{201C}open Safari\u{201D}.",
                "Start with \u{201C}Claude,\u{201D} to send a question straight to the cloud brain.")
            tip("rectangle.on.rectangle", "Drag a window by its title bar to the notch or a screen edge.",
                "It waits on the side. Point at the edge to get it back.")
            tip("book", "Everything else is in Settings › Features.",
                "A short guide to each part, with things to try.")
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func tip(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(state.skin.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
