import JarvisKit
import SwiftUI

/// The Finder tab: a folder drawn by Jarvis (Downloads at first, or the folder of a Finder window dropped in).
/// Drop files on it to move them in (Option copies), drag them out to anywhere. Double-click opens a file or
/// goes into a folder; the arrow goes up. Drag the title off the notch to open it as a Finder window there.
/// The search field searches the whole Mac by name (Spotlight); its results take the folder's place until it's
/// cleared or one of them (a folder) is opened.
struct FolderShelfView: View {
    let state: AppState
    let dock: DockController
    @State private var targeted = false
    @State private var query = ""
    @State private var search = FileSearch()
    @State private var thumbnails = ThumbnailCache()

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The shown folder's items, or the search's results.
    private var items: [ShelfItem] { searching ? search.results : dock.items }

    var body: some View {
        let tint = state.skin.foreground
        HStack(alignment: .top, spacing: 8) {
            FinderSidebar(state: state, dock: dock)
            folder(tint: tint)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(state.skin.surface), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let edge = state.skin.surfaceEdge {
                RoundedRectangle(cornerRadius: 12).strokeBorder(edge, lineWidth: 1)
            }
        }
        .onChange(of: query) { search.search(query) }
        // Opening a folder (from the results too) ends the search.
        .onChange(of: dock.shown) { query = "" }
        .onDisappear(perform: search.stop)
    }

    private func folder(tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(tint: tint)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 4)], spacing: 6) {
                    ForEach(items) { item in
                        ShelfItemView(item: item, tint: tint, thumbnails: thumbnails)
                            .overlay {
                                FileDragSource(url: item.url, open: { dock.open(item) }, menu: { menu(for: item) },
                                               moved: dock.fileDragMoved, ended: dock.fileDragEnded)
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if searching, items.isEmpty {
                    Text(search.searching ? "Searching your Mac\u{2026}" : "Nothing called \u{201C}\(query)\u{201D} on this Mac")
                        .font(.caption).foregroundStyle(tint.opacity(0.4))
                } else if !searching, dock.items.isEmpty {
                    Text("Empty folder: drop files here").font(.caption).foregroundStyle(tint.opacity(0.4))
                }
            }
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(state.skin.accent.opacity(targeted ? 0.1 : 0))
                .strokeBorder(targeted ? state.skin.accent : .clear, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .dropDestination(for: URL.self) { urls, _ in dock.drop(urls) } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }

    private func menu(for item: ShelfItem) -> [(String, () -> Void)] {
        var items: [(String, () -> Void)] = []
        if item.isFolder && !state.settings.finderPins.contains(item.url.path) {
            items.append(("Add to Sidebar", { state.update { $0.finderPins.append(item.url.path) } }))
        }
        items.append(("Show in Finder", { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }))
        return items
    }

    private func header(tint: Color) -> some View {
        HStack(spacing: 6) {
            if dock.canGoUp {
                Button(action: dock.showParent) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("Up one folder")
            }
            let icon = NSWorkspace.shared.icon(forFile: dock.shown.path)
            Label {
                Text(searching ? "This Mac" : FileManager.default.displayName(atPath: dock.shown.path)).lineLimit(1)
            } icon: {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            .font(.caption.weight(.semibold))
            .help("Drag off the notch to open it in Finder there")
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { _ in dock.dragOut(icon: icon) }
                .onEnded { _ in dock.endDragOut(dock.releaseFolder) })
            Spacer(minLength: 4)
            SearchField(query: $query, tint: tint, accent: state.skin.accent)
            Text(searching ? (items.count >= FileSearch.limit ? "\(items.count)+ found" : "\(items.count) found")
                           : "\(dock.items.count) items")
                .font(.caption2)
                .foregroundStyle(tint.opacity(0.5))
                .fixedSize()
        }
    }
}

/// A small rounded field with a magnifying glass, like Finder's search; the x clears it.
private struct SearchField: View {
    @Binding var query: String
    let tint: Color
    let accent: Color
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(focused ? accent : tint.opacity(0.5))
            TextField("Search Mac", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { query = ""; focused = false }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint.opacity(0.5))
                    .help("Clear the search")
            }
        }
        .font(.caption)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(width: 150)
        .background(tint.opacity(focused ? 0.14 : 0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(focused ? accent.opacity(0.6) : .clear, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let tint: Color
    let thumbnails: ThumbnailCache

    var body: some View {
        VStack(spacing: 2) {
            FileThumbnail(url: item.url, size: 32, thumbnails: thumbnails)
            Text(item.name)
                .font(.system(size: 9.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
        }
        .frame(width: 66, height: 58, alignment: .top)
        .contentShape(Rectangle())
        // Where it is, which matters for search results from anywhere on the Mac.
        .help(item.url.path)
    }
}
