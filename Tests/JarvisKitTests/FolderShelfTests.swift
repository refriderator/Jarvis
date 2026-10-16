import Foundation
import JarvisKit
import Testing

struct FolderShelfTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "shelf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "in"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "out/sub"), withIntermediateDirectories: true)
        for name in ["file10.txt", "file2.txt", ".hidden"] {
            try Data().write(to: root.appending(path: "in/\(name)"))
        }
    }

    @Test func listsFoldersFirstThenNaturalOrderWithoutHidden() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "in/zeta"), withIntermediateDirectories: true)
        let names = FolderShelf.list(root.appending(path: "in")).map(\.name)
        #expect(names == ["zeta", "file2.txt", "file10.txt"])
    }

    @Test func dropMovesOnTheSameDiskAndNeverOverwrites() throws {
        let out = root.appending(path: "out")
        try Data().write(to: out.appending(path: "file2.txt"))
        let moved = FolderShelf.drop([root.appending(path: "in/file2.txt")], into: out)
        #expect(moved.map(\.lastPathComponent) == ["file2 2.txt"])
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "in/file2.txt").path))
    }

    @Test func optionCopies() {
        let source = root.appending(path: "in/file10.txt")
        FolderShelf.drop([source], into: root.appending(path: "out"), copy: true)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "out/file10.txt").path))
    }

    @Test func droppingIntoItsOwnFolderOrItselfDoesNothing() {
        #expect(FolderShelf.drop([root.appending(path: "in/file2.txt")], into: root.appending(path: "in")).isEmpty)
        #expect(FolderShelf.drop([root.appending(path: "out")], into: root.appending(path: "out")).isEmpty)
    }
}
