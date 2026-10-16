import Foundation

/// A page pinned to the browser's start page, shown as a symbol (its first letter, or the site's icon).
public struct Bookmark: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var name: String
    public var url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// One tab of the Web tab's browser. No address means the start page (the bookmarks).
public struct BrowserTab: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public var url: URL?
    public var title = ""

    public init(url: URL? = nil) {
        self.url = url
    }

    /// What the tab strip shows: the page's title, else its site, else "New Tab".
    public var label: String {
        if !title.isEmpty { return title }
        return url?.host(percentEncoded: false)?.replacing(/^www\./, with: "") ?? "New Tab"
    }
}

/// The browser's tabs, in order, and which one is showing. There is always at least one.
public struct BrowserTabs: Equatable, Sendable {
    public private(set) var tabs = [BrowserTab()]
    public private(set) var selected: BrowserTab.ID

    public init() {
        selected = tabs[0].id
    }

    public var current: BrowserTab { tabs.first { $0.id == selected } ?? tabs[0] }

    /// A new tab right after the one showing, and shows it.
    @discardableResult public mutating func open(_ url: URL? = nil) -> BrowserTab.ID {
        let tab = BrowserTab(url: url)
        let at = tabs.firstIndex { $0.id == selected }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: at)
        selected = tab.id
        return tab.id
    }

    public mutating func select(_ id: BrowserTab.ID) {
        if tabs.contains(where: { $0.id == id }) { selected = id }
    }

    /// Closing the tab showing shows the one after it (or before, if it was last). Closing the last tab leaves a
    /// fresh start page.
    public mutating func close(_ id: BrowserTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty { tabs = [BrowserTab()] }
        if selected == id { selected = tabs[min(index, tabs.count - 1)].id }
    }

    /// Drag-to-reorder: the tab goes where `target` is, the others shifting to make room.
    public mutating func move(_ id: BrowserTab.ID, to target: BrowserTab.ID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.insert(tabs.remove(at: from), at: to)
    }

    /// The page a tab is on, as the web view reports it.
    public mutating func update(_ id: BrowserTab.ID, url: URL?, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        tabs[index].title = title
    }

    /// What was typed in the address field: an address ("apple.com", "https://..."), else a web search.
    public static func address(_ typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil {
            return url
        }
        // A word with a dot and no spaces is a site ("apple.com", "localhost:8080" too).
        let scheme = text.hasPrefix("localhost") ? "http://" : "https://"
        if !text.contains(" "), text.contains(".") || text.hasPrefix("localhost"), let url = URL(string: scheme + text),
           url.host() != nil {
            return url
        }
        var search = URLComponents(string: "https://www.google.com/search")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}
