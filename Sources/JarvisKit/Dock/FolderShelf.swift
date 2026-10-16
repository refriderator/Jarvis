import Foundation

/// One file or folder in the notch's folder view.
public struct ShelfItem: Sendable, Equatable, Identifiable {
    public let url: URL
    public let isFolder: Bool
    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, isFolder: Bool) {
        self.url = url
        self.isFolder = isFolder
    }
}

/// Lists a folder the way Finder would by default, and files dropped on it the way Finder would.
public enum FolderShelf {
    /// Visible items only; folders first, then by name as Finder sorts it ("file2" before "file10").
    public static func list(_ folder: URL, fileManager: FileManager = .default) -> [ShelfItem] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            // An app or other package is one thing to the user, like a file.
            return ShelfItem(url: url, isFolder: values?.isDirectory == true && values?.isPackage != true)
        }
        .sorted { a, b in
            a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Finder's rule: dropped on the same disk it moves, from another disk it copies (`copy` forces a copy,
    /// like holding Option). A name already there gets " 2", " 3"... instead of replacing anything.
    /// Returns where each one ended up.
    @discardableResult
    public static func drop(_ urls: [URL], into folder: URL, copy: Bool = false,
                            fileManager: FileManager = .default) -> [URL] {
        let folderVolume = volume(of: folder)
        return urls.compactMap { source in
            // Dropping something back where it already is does nothing.
            guard source.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL,
                  source.standardizedFileURL != folder.standardizedFileURL else { return nil }
            let target = freeName(for: source.lastPathComponent, in: folder, fileManager: fileManager)
            do {
                if copy || volume(of: source) != folderVolume {
                    try fileManager.copyItem(at: source, to: target)
                } else {
                    try fileManager.moveItem(at: source, to: target)
                }
                return target
            } catch {
                return nil
            }
        }
    }

    static func freeName(for name: String, in folder: URL, fileManager: FileManager) -> URL {
        var target = folder.appending(path: name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while fileManager.fileExists(atPath: target.path) {
            target = folder.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return target
    }

    private static func volume(of url: URL) -> URL? {
        try? url.resourceValues(forKeys: [.volumeURLKey]).volume
    }
}

/// The Finder tab's sidebar: Finder's standard places, then folders the user pinned, then iCloud Drive.
/// (Finder's own sidebar list is private to Finder, so Jarvis keeps its own pins.)
public struct SidebarPlace: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    /// An SF Symbol, matching Finder's sidebar.
    public let symbol: String
    public let pinned: Bool
    public var id: URL { url }

    public static func favorites(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SidebarPlace] {
        [SidebarPlace(url: URL(filePath: "/Applications"), name: "Applications", symbol: "app.badge", pinned: false),
         SidebarPlace(url: home.appending(path: "Desktop"), name: "Desktop", symbol: "menubar.dock.rectangle", pinned: false),
         SidebarPlace(url: home.appending(path: "Documents"), name: "Documents", symbol: "doc", pinned: false),
         SidebarPlace(url: home.appending(path: "Downloads"), name: "Downloads", symbol: "arrow.down.circle", pinned: false),
         SidebarPlace(url: home, name: home.lastPathComponent, symbol: "house", pinned: false)]
    }

    public static func pins(_ paths: [String]) -> [SidebarPlace] {
        paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { SidebarPlace(url: $0, name: $0.lastPathComponent, symbol: "folder", pinned: true) }
    }

    public static func locations(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SidebarPlace] {
        let icloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: icloud.path) else { return [] }
        return [SidebarPlace(url: icloud, name: "iCloud Drive", symbol: "icloud", pinned: false)]
    }
}
