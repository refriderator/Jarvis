import JarvisKit
import SwiftUI

struct AppearanceTab: View {
    let state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Skin", selection: state.binding(\.skinID)) {
                    ForEach(SkinCatalog.all) { skin in
                        Text(skin.name).tag(skin.id)
                    }
                }
                .pickerStyle(.radioGroup)
                Picker("Caption size", selection: state.binding(\.captionSize)) {
                    Text("Small").tag(CaptionSize.small)
                    Text("Regular").tag(CaptionSize.regular)
                    Text("Large").tag(CaptionSize.large)
                }
                .pickerStyle(.segmented)
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
                Text("Dock Cards")
            } footer: {
                Text("Drag a window by its title bar onto the notch, or to the left or right edge, to hold it there. Point at the edge to see it; click it to use it. Drag it by its title bar into the middle to let it go. Needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
