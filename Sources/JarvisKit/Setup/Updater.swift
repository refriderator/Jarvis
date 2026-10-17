import Foundation

/// Updates Jarvis from inside Settings: pulls the folder it was built from and runs the installer again.
public enum Updater {
    /// The git checkout this copy was built from (scripts/bundle.sh writes it into Info.plist), if it's still there.
    public static var sourceFolder: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "JarvisSourceFolder") as? String else { return nil }
        let folder = URL(fileURLWithPath: path)
        let isCheckout = FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
            && FileManager.default.fileExists(atPath: folder.appending(path: "Install Jarvis.command").path)
        return isCheckout ? folder : nil
    }

    /// Runs in a Terminal window: the installer quits and reopens Jarvis, and any error (or Apple's license) shows there.
    @MainActor
    public static func openUpdate() throws {
        guard let folder = sourceFolder else { throw ChatError("Can't find the folder Jarvis was installed from.") }
        try TerminalWindow.run("""
            echo "Updating Jarvis. Jarvis will quit and open again when it's done."
            echo
            cd \(TerminalWindow.quoted(folder.path)) && git pull && sh "Install Jarvis.command"
            """, named: "Update Jarvis")
    }
}
