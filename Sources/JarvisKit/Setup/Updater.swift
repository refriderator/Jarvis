import AppKit
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
        let quoted = "'" + folder.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let script = """
            #!/bin/sh
            clear
            echo "Updating Jarvis. Jarvis will quit and open again when it's done."
            echo
            cd \(quoted) && git pull && sh "Install Jarvis.command"
            """
        let url = URL.temporaryDirectory.appending(path: "Update Jarvis.command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }
}
