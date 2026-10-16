import Foundation
import Observation

/// Searches the whole Mac by name with Spotlight, for the Finder tab's search field. Results come in as
/// Spotlight finds them, best known first (folders, then by name), up to `limit`.
@MainActor
@Observable
public final class FileSearch {
    public private(set) var results: [ShelfItem] = []
    /// Still looking (Spotlight's first pass hasn't finished).
    public private(set) var searching = false
    public static let limit = 120

    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pending: DispatchWorkItem?

    public init() {}

    /// Searches for `text` a moment after typing stops; empty clears the results.
    public func search(_ text: String) {
        pending?.cancel()
        let words = text.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return stop() }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.start(words) } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    public func stop() {
        pending?.cancel()
        query?.stop()
        query = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        results = []
        searching = false
    }

    private func start(_ words: String) {
        stop()
        let query = NSMetadataQuery()
        // Every word somewhere in the name, ignoring case and accents, like Finder's search bar does by name.
        query.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: words.split(separator: " ").map {
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, String($0))
        })
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.notificationBatchingInterval = 0.15
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                let done = note.name == .NSMetadataQueryDidFinishGathering
                MainActor.assumeIsolated { self?.collect(done: done) }
            })
        }
        self.query = query
        searching = true
        query.start()
    }

    private func collect(done: Bool) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let count = min(query.resultCount, Self.limit * 4)
        var items: [ShelfItem] = []
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  // Inside apps and libraries is noise for a name search.
                  !path.contains("/Library/"), !path.contains(".app/") else { continue }
            let url = URL(filePath: path)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            items.append(ShelfItem(url: url, isFolder: values?.isDirectory == true && values?.isPackage != true))
        }
        results = Array(items.sorted { a, b in
            a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }.prefix(Self.limit))
        if done { searching = false }
    }
}
