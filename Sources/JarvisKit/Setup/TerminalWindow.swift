import AppKit
import Foundation

/// Runs a shell script in a new Terminal window, for jobs the user should watch or answer (updating, uninstalling).
public enum TerminalWindow {
    /// `name` is the window's title (the script's file name, without ".command").
    @MainActor
    public static func run(_ body: String, named name: String) throws {
        let url = URL.temporaryDirectory.appending(path: "\(name).command")
        try "#!/bin/sh\nclear\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    /// `path` quoted for the shell.
    public static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
