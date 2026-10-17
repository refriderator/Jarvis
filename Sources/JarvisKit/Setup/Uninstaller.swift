import Foundation

/// Removes Jarvis from inside Settings: scripts/uninstall.sh, which `bundle.sh` puts inside the app, run in a
/// Terminal window that lists what goes and asks first.
public enum Uninstaller {
    /// The script deletes the app it came from, so it runs from a copy outside it.
    @MainActor
    public static func openUninstall() throws {
        guard let script = Bundle.main.url(forResource: "uninstall", withExtension: "sh") else {
            throw ChatError("This copy of Jarvis has no uninstaller. Run scripts/uninstall.sh from its folder.")
        }
        let copy = URL.temporaryDirectory.appending(path: "jarvis-uninstall.sh")
        try? FileManager.default.removeItem(at: copy)
        try FileManager.default.copyItem(at: script, to: copy)
        let source = Updater.sourceFolder.map { " " + TerminalWindow.quoted($0.path) } ?? ""
        try TerminalWindow.run("sh \(TerminalWindow.quoted(copy.path))\(source)", named: "Uninstall Jarvis")
    }
}
