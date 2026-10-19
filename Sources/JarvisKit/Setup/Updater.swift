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

/// A release newer than this copy, on GitHub.
public struct Release: Sendable, Equatable {
    public let version: AppVersion
    /// Its page on GitHub, with its notes.
    public let page: URL
}

extension Updater {
    /// The release this copy was built from: scripts/bundle.sh writes the latest tag into Info.plist (0.1.0 before
    /// the first release).
    public static var installedVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    /// "owner/name" of the GitHub repository this copy was built from (bundle.sh), nil if it wasn't one.
    public static var repository: String? {
        Bundle.main.object(forInfoDictionaryKey: "JarvisRepository") as? String
    }

    /// The newest release on GitHub when it's newer than this copy, else nil (and nil when it can't be told:
    /// offline, no releases yet). One request, no account needed: GitHub allows 60 an hour, Jarvis asks once a day.
    public static func newerRelease() async -> Release? {
        guard let repository, let installed = installedVersion,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Jarvis", forHTTPHeaderField: "User-Agent")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? decoder.decode(LatestRelease.self, from: data),
              let version = AppVersion(latest.tagName), version > installed,
              let page = URL(string: latest.htmlUrl) else { return nil }
        return Release(version: version, page: page)
    }

    /// The fields of GitHub's answer that matter here.
    private struct LatestRelease: Decodable {
        let tagName: String
        let htmlUrl: String
    }
}
