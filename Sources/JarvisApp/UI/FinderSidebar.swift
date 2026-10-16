import JarvisKit
import SwiftUI

/// The Finder tab's sidebar, like Finder's: Favorites (with pinned folders after them) and Locations. Drop a
/// folder on it to pin it; right-click a pin to remove it.
struct FinderSidebar: View {
    let state: AppState
    let dock: DockController
    @State private var targeted = false

    var body: some View {
        let tint = state.skin.foreground
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                section("Favorites", SidebarPlace.favorites() + SidebarPlace.pins(state.settings.finderPins), tint: tint)
                let locations = SidebarPlace.locations()
                if !locations.isEmpty { section("Locations", locations, tint: tint) }
            }
        }
        .scrollIndicators(.never)
        .frame(width: 118)
        .background(targeted ? state.skin.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: URL.self) { urls, _ in pin(urls) } isTargeted: { targeted = $0 }
    }

    @ViewBuilder
    private func section(_ title: String, _ places: [SidebarPlace], tint: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint.opacity(0.45))
            .padding(.leading, 6)
            .padding(.top, 4)
        ForEach(places) { place in
            let on = dock.shown.standardizedFileURL == place.url.standardizedFileURL
            Button { dock.show(place.url) } label: {
                Label {
                    Text(place.name).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: place.symbol).foregroundStyle(state.skin.accent).frame(width: 14)
                }
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(on ? tint.opacity(state.skin.surface + 0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                if place.pinned {
                    Button("Remove from Sidebar") { unpin(place.url) }
                }
            }
        }
    }

    /// Folders dropped here are pinned, never moved.
    private func pin(_ urls: [URL]) -> Bool {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard !folders.isEmpty else { return false }
        state.update { settings in
            for folder in folders where !settings.finderPins.contains(folder.path) {
                settings.finderPins.append(folder.path)
            }
        }
        return true
    }

    private func unpin(_ url: URL) {
        state.update { $0.finderPins.removeAll { $0 == url.path } }
    }
}
