import JarvisKit
import SwiftUI

/// A new tab's page: the bookmarks as round symbols (the site's icon, else its first letter; the name shows on
/// hover), so it stays uncluttered. The + adds one, named; drag one to move it (the others make room); right-click
/// removes one.
struct StartPage: View {
    let browser: BrowserController
    let tint: Color
    let accent: Color
    @State private var adding = false
    @State private var dragging: Bookmark.ID?
    @State private var name = ""
    @State private var address = ""

    var body: some View {
        Group {
            if adding {
                form
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.size), spacing: 14)], spacing: 14) {
                        ForEach(browser.bookmarks) { bookmark in
                            Button { browser.go(to: bookmark.url) } label: { BookmarkSymbol(bookmark: bookmark, tint: tint) }
                                .buttonStyle(.plain)
                                .help(bookmark.name)
                                .contextMenu {
                                    Button("Remove \u{201C}\(bookmark.name)\u{201D}", role: .destructive) { browser.removeBookmark(bookmark) }
                                }
                                .reorderable(bookmark.id, dragging: $dragging, move: browser.moveBookmark)
                        }
                        Button { adding = true } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .frame(width: Self.size, height: Self.size)
                                .foregroundStyle(tint.opacity(0.6))
                                .background(Circle().strokeBorder(tint.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Add a bookmark")
                    }
                    .padding(14)
                }
                .endsReorder(dragging: $dragging)
                .scrollIndicators(.never)
                .overlay(alignment: .bottom) {
                    if browser.bookmarks.isEmpty {
                        Text("Add the sites you use most with +, or type an address above.")
                            .font(.caption).foregroundStyle(tint.opacity(0.4)).padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    static let size: CGFloat = 40

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New bookmark").font(.caption.weight(.semibold)).foregroundStyle(tint.opacity(0.7))
            field("Name", text: $name)
            field("Address, e.g. quercus.utoronto.ca", text: $address)
                .onSubmit(add)
            HStack {
                Button("Cancel") { reset() }
                Button("Add", action: add)
                    .disabled(BrowserTabs.address(address) == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint.opacity(0.08), in: Capsule())
    }

    private func add() {
        guard BrowserTabs.address(address) != nil else { return }
        browser.addBookmark(name: name, typed: address)
        reset()
    }

    private func reset() {
        adding = false
        name = ""
        address = ""
    }
}

/// A bookmark's round symbol: the site's own icon, or its first letter until (or unless) that loads.
private struct BookmarkSymbol: View {
    let bookmark: Bookmark
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.1))
            Text(bookmark.name.prefix(1).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint.opacity(0.75))
            if let icon = URL(string: "/apple-touch-icon.png", relativeTo: bookmark.url) {
                AsyncImage(url: icon) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            }
        }
        .frame(width: StartPage.size, height: StartPage.size)
        .contentShape(Circle())
    }
}
