import JarvisKit
import SwiftUI

/// The Settings window: a form over `Settings`, one tab per area.
struct SettingsView: View {
    let state: AppState
    let downloader: ModelDownloader

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralTab(state: state) }
            Tab("Voice", systemImage: "waveform") { VoiceTab(state: state) }
            Tab("Appearance", systemImage: "paintpalette") { AppearanceTab(state: state) }
            Tab("Connections", systemImage: "link") { ConnectionsTab(state: state, downloader: downloader) }
            Tab("Usage", systemImage: "number") { UsageTab(state: state) }
            Tab("Features", systemImage: "book") { FeaturesTab(state: state) }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 500)
    }
}
