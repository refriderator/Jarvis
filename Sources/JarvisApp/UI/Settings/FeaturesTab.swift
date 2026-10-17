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
                    how: ["Click the notch and type, or press the mic.",
                          "From any app: **Option-Space** to talk, **Option-Shift-Space** to type. **Esc** stops it talking.",
                          "Click the caption to keep it on screen. **Summarize** turns a long cloud answer into a few points.",
                          "Follow-ups work for 5 minutes."],
                    tryIt: ["what's 15% of 84", "write a short thank-you note"],
                    settings: "Settings › General (shortcuts), Voice (how talking works)"),
            Feature(icon: "cpu", title: "Who answers", summary: "Free on this Mac first, a cloud AI when it's needed.",
                    how: ["The **local brain** does the quick jobs: maths, today's and tomorrow's calendar, apps and windows. Notion questions go to the cloud brain.",
                          "Everything else (facts, explanations, writing) goes to the **cloud brain**: Claude or Codex.",
                          "Start with **Claude,** to skip the local brain.",
                          "**Claude's access** sets what the cloud brain may do on this Mac: nothing, Jarvis's tools, or everything.",
                          "**Token saving** asks before anything goes to the cloud."],
                    tryIt: ["Claude, explain how a transistor works"],
                    settings: "Settings › Connections"),
            Feature(icon: "camera", title: "Camera", summary: "Ask it to look at something.",
                    how: ["Takes one photo only when you ask it to look.",
                          "Needs a Claude cloud brain."],
                    tryIt: ["what am I holding?", "take a look at this"]),
        ]),
        ("Your day", [
            Feature(icon: "sun.horizon", title: "Morning brief", summary: "Your day in a few sentences.",
                    how: ["The date, what to wear, the weather, and what's left on your calendar and in Notion.",
                          "Weather questions get just the weather."],
                    tryIt: ["good morning", "do I need an umbrella?"]),
            Feature(icon: "calendar", title: "Calendar", summary: "Read and add events.",
                    how: ["Add Google, Outlook, iCloud and others in System Settings › Internet Accounts.",
                          "Today's events show in the open notch under **Today**."],
                    tryIt: ["what's on tomorrow?", "add dentist to my calendar Friday at 3pm"],
                    settings: "Settings › Connections › Services"),
            Feature(icon: "timer", title: "Timers and reminders", summary: "Instant.",
                    how: ["Timers and reminders only (no alarms). Running ones show at the top of the Today list; click × to cancel one."],
                    tryIt: ["set a timer for 10 minutes", "remind me in an hour to stretch", "remind me at 7 pm to call mom", "cancel the timer"]),
            Feature(icon: "checklist", title: "Notion", summary: "What's due, reading pages, ticking things off.",
                    how: ["Make an integration at notion.so/my-integrations and paste its token in Settings.",
                          "In Notion, open each page it may use › ••• › Connections › add your integration."],
                    tryIt: ["what's due this week?", "when is my next exam?"],
                    settings: "Settings › Connections › Services"),
            Feature(icon: "music.note", title: "Music", summary: "What's playing in Music or Spotify.",
                    how: ["Play, pause and skip in the open notch. Click the song to open the player."]),
        ]),
        ("In the notch", [
            Feature(icon: "folder", title: "Finder", summary: "A folder you can use without opening Finder.",
                    how: ["Drop files on it to move them in (hold **Option** to copy); drag them out anywhere.",
                          "Double-click to open; the search field searches the whole Mac.",
                          "Drag a Finder window onto the notch to show that folder here."]),
            Feature(icon: "globe", title: "Web", summary: "A small browser with tabs and bookmarks.",
                    how: ["Type an address or a search. Drag tabs to reorder; × closes one.",
                          "Bookmarks: **+** to add, drag to reorder, right-click to remove.",
                          "The arrows button makes it bigger or smaller. **⌘−** / **⌘=** zoom.",
                          "A full-screen video keeps playing in the closed notch: hover to peek, **Esc** to pause.",
                          "Saves passwords to your Keychain, on secure sites only."]),
            Feature(icon: "chart.xyaxis.line", title: "Monitor", summary: "CPU, memory and network at a glance.",
                    how: ["Open the notch and pick the Monitor tab."]),
            Feature(icon: "display", title: "Another display", summary: "Put the notch on any display.",
                    how: ["Pick the display in the menu-bar menu (**Notch On**) or Settings › Display.",
                          "Without a real notch there, the bar shows the time, date, song, weather and more, one at a time."],
                    settings: "Settings › Display"),
            Feature(icon: "pin", title: "Keep Info", summary: "Keep the open notch open.",
                    how: ["Turn on **Keep Info**. Turn it off or press **Esc** to let it close."]),
        ]),
        ("Windows and video", [
            Feature(icon: "rectangle.on.rectangle", title: "Holding windows", summary: "Set windows aside on the sides of the screen.",
                    how: ["Drag a window by its title bar onto the notch and let go on the box, or onto the left or "
                          + "right edge of the screen.",
                          "Point at that edge to see its windows. Click one to use it there; it slides back when the "
                          + "pointer leaves.",
                          "To let one go, drag it by its title bar into the middle of the screen.",
                          "Up to six per desktop."],
                    settings: "Settings › General › Hold windows in the notch (needs Accessibility)"),
            Feature(icon: "square.stack.3d.up", title: "Quick Dock", summary: "One window at a time on each desktop.",
                    how: ["The app you switch to fills the desktop; the rest wait on the side. Click one to swap it in.",
                          "While it's on, the menu-bar icon has a dot in its corner."],
                    tryIt: ["turn on Quick Dock"],
                    settings: "Settings › General › Quick Dock"),
            Feature(icon: "macwindow", title: "Apps and windows by voice", summary: "Open apps, set windows aside.",
                    how: ["Needs Accessibility, like holding windows."],
                    tryIt: ["open Safari", "dock this window", "bring back Safari"]),
            Feature(icon: "pip", title: "Picture in Picture", summary: "Keep a browser's floating video in the notch.",
                    how: ["Start Picture in Picture in Safari, Chrome or Firefox, then press **Video** in the notch "
                          + "(or drag the video onto it).",
                          "**↓** makes it bigger, **↑** smaller, down to tucked beside the notch.",
                          "Press **Video** again, or drag it away, to let it go."]),
        ]),
        ("Make it yours", [
            Feature(icon: "person.text.rectangle", title: "Name", summary: "Call your assistant something else.",
                    how: ["Type a name; the field warns about ones that cause trouble."],
                    settings: "Settings › General › Name"),
            Feature(icon: "paintpalette", title: "Skins and captions", summary: "Six looks, three caption sizes.",
                    how: ["Liquid Glass is see-through; the others are solid colours."],
                    settings: "Settings › Appearance"),
            Feature(icon: "person.wave.2", title: "Voice", summary: "Any installed voice, including Personal Voice.",
                    how: ["Get better voices in System Settings › Accessibility › Spoken Content › System Voice › "
                          + "Manage Voices."],
                    settings: "Settings › Voice"),
            Feature(icon: "doc.text.magnifyingglass", title: "Conversation log", summary: "A record of every question.",
                    how: ["Off unless turned on. One file a day, on this Mac only."],
                    settings: "Settings › Connections › Training"),
        ]),
    ]
}
