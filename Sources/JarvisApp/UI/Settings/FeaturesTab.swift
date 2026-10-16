import JarvisKit
import SwiftUI

/// Settings › Features: a short guide to each part of Jarvis, searchable. Each entry says what it is, how to use
/// it, and where its settings are; the welcome only covers the essentials and points here for the rest.
struct FeaturesTab: View {
    let state: AppState
    @State private var search = ""

    private var shown: [(String, [Feature])] {
        let words = search.lowercased().split(separator: " ")
        return Feature.groups.compactMap { group, features in
            let matching = features.filter { feature in
                let text = ([feature.title, feature.summary] + feature.how + feature.tryIt).joined(separator: " ").lowercased()
                return words.allSatisfy { text.contains($0) }
            }
            return matching.isEmpty ? nil : (group, matching)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Search features", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            ForEach(shown, id: \.0) { group, features in
                Section(group) {
                    ForEach(features) { feature in
                        FeatureRow(feature: feature, accent: state.skin.accent, startsOpen: !search.isEmpty)
                    }
                }
            }
            if shown.isEmpty {
                Text("Nothing about \u{201C}\(search)\u{201D}.").foregroundStyle(.secondary)
            }
        }
    }
}

private struct FeatureRow: View {
    let feature: Feature
    let accent: Color
    let startsOpen: Bool
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { open || startsOpen }, set: { open = $0 })) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(feature.how, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(.init(line)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !feature.tryIt.isEmpty {
                    Text("Try: " + feature.tryIt.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
                        .foregroundStyle(accent)
                }
                if let place = feature.settings {
                    Label(place, systemImage: "gearshape").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: feature.icon).frame(width: 20).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(feature.title).font(.body.weight(.medium))
                    Text(feature.summary).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One entry in the guide.
struct Feature: Identifiable {
    let icon: String
    let title: String
    let summary: String
    /// How to use it, a line each (Markdown: **bold**, `keys`).
    let how: [String]
    /// Things to say or type.
    var tryIt: [String] = []
    /// Where its settings are.
    var settings: String? = nil

    var id: String { title }

    static let groups: [(String, [Feature])] = [
        ("Asking", [
            Feature(icon: "waveform", title: "Talk or type", summary: "Ask anything; the answer is spoken and captioned.",
                    how: ["Click (or hover) the notch and type, or press the mic.",
                          "From any app: **Option-Space** to talk, **Option-Shift-Space** to type. **Esc** stops it talking.",
                          "Click the caption to keep it on screen; it grows to fit long answers.",
                          "Follow-ups work: the last few answers from the past 5 minutes go along with a question."],
                    tryIt: ["what's 15% of 84", "write a short thank-you note"],
                    settings: "Settings › General (shortcuts), Voice (how talking works)"),
            Feature(icon: "cpu", title: "Who answers", summary: "Free on this Mac first, a cloud AI when it's needed.",
                    how: ["The **local brain** (Apple's model, the built-in one, or Ollama) tries first. When it isn't sure, "
                          + "or the question is about news or something recent, the **cloud brain** answers.",
                          "Start with **Claude,** to send a question straight to the cloud brain.",
                          "**Token saving** asks before anything goes to the cloud, so tokens are only used when you say so.",
                          "The Usage tab counts tokens (never money)."],
                    tryIt: ["Claude, explain how a transistor works"],
                    settings: "Settings › Connections"),
            Feature(icon: "camera", title: "Camera", summary: "Ask it to look at something.",
                    how: ["Takes one photo only when a question asks it to look, and sends it with the question.",
                          "Needs a Claude cloud brain (Claude Code or an API key)."],
                    tryIt: ["what am I holding?", "take a look at this"]),
        ]),
        ("Your day", [
            Feature(icon: "calendar", title: "Calendar", summary: "Read and add events from any calendar on your Mac.",
                    how: ["Uses the calendars in macOS's Calendar app: add Google, Outlook, iCloud and others in "
                          + "System Settings › Internet Accounts.",
                          "Today's events show in the open notch under **Today**."],
                    tryIt: ["what's on tomorrow?", "add dentist to my calendar Friday at 3pm"],
                    settings: "Settings › Connections › Services"),
            Feature(icon: "timer", title: "Timers and reminders", summary: "Instant, no AI needed.",
                    how: ["Running timers show at the top of the Today list; click × to cancel one."],
                    tryIt: ["set a timer for 10 minutes", "remind me in an hour", "cancel the timer"]),
            Feature(icon: "checklist", title: "Notion", summary: "What's due, reading pages, ticking things off.",
                    how: ["Make an integration at notion.so/my-integrations and paste its token in Settings.",
                          "In Notion, open each page it may use › ••• › Connections › add your integration.",
                          "Works with a Claude cloud brain, or a local model that can use tools."],
                    tryIt: ["what's due this week?", "when is my next exam?"],
                    settings: "Settings › Connections › Services"),
            Feature(icon: "music.note", title: "Music", summary: "What's playing in Music or Spotify.",
                    how: ["Shows in the open notch with play, pause and skip. Click the song to open the player."]),
        ]),
        ("In the notch", [
            Feature(icon: "folder", title: "Finder", summary: "A folder you can use without opening Finder.",
                    how: ["Drop files on it to move them in (hold **Option** to copy); drag them out anywhere.",
                          "Double-click to open; the search field searches the whole Mac.",
                          "Drag a Finder window onto the notch to show that folder here. Pin folders to the sidebar."]),
            Feature(icon: "globe", title: "Web", summary: "A small browser with tabs and bookmarks.",
                    how: ["Tabs: click to show, × to close, drag to reorder. Back and forward buttons; type an address or a search.",
                          "The start page shows bookmarks as symbols: **+** to add, drag to reorder, right-click to remove.",
                          "The arrows button switches between a small and a large browser. **⌘−** / **⌘=** zoom the page.",
                          "A video's full-screen button fills the browser. Closed, the notch then shows it as a small "
                          + "player: hover to peek, click to open, **Esc** to pause it.",
                          "It can save passwords to your Keychain, only on secure, public sites."]),
            Feature(icon: "chart.xyaxis.line", title: "Monitor", summary: "CPU, memory and network at a glance.",
                    how: ["Updated once a second, only while the tab is showing."]),
            Feature(icon: "pin", title: "Keep Info", summary: "Keep the open notch open.",
                    how: ["Normally it closes when the pointer leaves. With **Keep Info** on, it stays until you turn it "
                          + "off or press **Esc**."]),
        ]),
        ("Windows and video", [
            Feature(icon: "rectangle.on.rectangle", title: "Holding windows", summary: "Set windows aside in the notch, like Stage Manager.",
                    how: ["Drag a window by its title bar onto the notch and let go on the box.",
                          "Its icon waits in a tab beside the notch. Click it to bring the window back; **Option-click** "
                          + "swaps it with the window in front; drag it out to place it.",
                          "Each desktop keeps its own, up to six."],
                    settings: "Settings › General › Hold windows in the notch (needs Accessibility)"),
            Feature(icon: "square.stack.3d.up", title: "Quick Dock", summary: "One window at a time on each desktop.",
                    how: ["The app you switch to fills the desktop; the rest wait in the notch. Clicking one swaps it in.",
                          "Turns itself off if you move desktops around in Mission Control."],
                    settings: "Settings › General › Quick Dock"),
            Feature(icon: "pip", title: "Picture in Picture", summary: "Keep a browser's floating video in the notch.",
                    how: ["Start Picture in Picture in Safari, Chrome or Firefox, then press **Video** in the notch "
                          + "(or drag the video onto it).",
                          "Closed, it plays as a mini player. Its **↓** tab makes it bigger, **↑** smaller, down to "
                          + "tucked away beside the notch.",
                          "Press **Video** again, or drag it away, to let it go."]),
        ]),
        ("Make it yours", [
            Feature(icon: "person.text.rectangle", title: "Name", summary: "Call your assistant something else.",
                    how: ["It's what it calls itself and what the notch shows; the app stays Jarvis.",
                          "Some names cause trouble (\u{201C}Claude\u{201D}, other assistants' names, command words): "
                          + "the name field warns about them."],
                    settings: "Settings › General › Name"),
            Feature(icon: "paintpalette", title: "Skins and captions", summary: "Six looks, three caption sizes.",
                    how: ["Liquid Glass is see-through; the others are solid colours."],
                    settings: "Settings › Appearance"),
            Feature(icon: "person.wave.2", title: "Voice", summary: "Any installed voice, including Personal Voice.",
                    how: ["Download better voices in System Settings › Accessibility › Spoken Content › System Voice › "
                          + "Manage Voices."],
                    settings: "Settings › Voice"),
            Feature(icon: "doc.text.magnifyingglass", title: "Conversation log", summary: "A raw record of every question.",
                    how: ["Off unless turned on. Saves the exact prompts and replies, one file a day, on this Mac only."],
                    settings: "Settings › Connections › Training"),
        ]),
    ]
}
