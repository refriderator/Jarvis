import AppKit
import ApplicationServices

/// The page in a browser, read as text.
public struct ScreenPage: Equatable, Sendable {
    public var app: String
    public var title: String
    public var text: String

    public init(app: String, title: String, text: String) {
        self.app = app
        self.title = title
        self.text = text
    }
}

/// What's in front of the user: the selected text in any app, or the page in the browser.
@MainActor
public protocol ScreenTextSource: Sendable {
    /// The selected text in the app in front, or nil when nothing is selected (or it can't be read).
    func selection() -> String?
    /// The page in the browser in front. Throws with what to do when it can't be read.
    func page() throws -> ScreenPage
    /// Puts text on the clipboard, for a rewrite to paste.
    func copy(_ text: String)
}

/// Reads the app in front: the selection through Accessibility (Jarvis already has it for held windows), and a
/// browser's page through AppleScript. Typing in the notch can bring Jarvis forward, so the last other app counts.
@MainActor
public final class MacScreenText: ScreenTextSource {
    private var lastApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    static let chromium: Set<String> = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac"]

    public init() {
        lastApp = Self.other(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app = Self.other(app) { self?.lastApp = app }
            }
        }
    }

    /// `app`, unless it's Jarvis itself.
    private static func other(_ app: NSRunningApplication?) -> NSRunningApplication? {
        app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
    }

    private var front: NSRunningApplication? { Self.other(NSWorkspace.shared.frontmostApplication) ?? lastApp }

    public func selection() -> String? {
        guard let app = front else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // A busy app would otherwise hold the main thread for the 6 s default.
        AXUIElementSetMessagingTimeout(element, 0.5)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func page() throws -> ScreenPage {
        guard let app = front, let id = app.bundleIdentifier else { throw ChatError("There's no page in front to read.") }
        let name = app.localizedName ?? "the browser"
        let script: String
        if id == "com.apple.Safari" {
            script = "tell application id \"\(id)\" to tell current tab of front window to return (name as text) & linefeed & (text as text)"
        } else if Self.chromium.contains(id) {
            script = "tell application id \"\(id)\" to tell active tab of front window to return (title as text) & linefeed & "
                + "(execute javascript \"document.body.innerText\")"
        } else {
            throw ChatError("I can read pages in Safari and Chrome. For \(name), select the text and ask me to summarize the selection.")
        }
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            if Self.chromium.contains(id) {
                throw ChatError("To let me read pages in \(name), turn on View › Developer › Allow JavaScript from Apple Events.")
            }
            throw ChatError("I couldn't read the page in \(name). Allow Jarvis to control it in System Settings › Privacy & Security › Automation.")
        }
        let parts = result.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let text = parts.count > 1 ? String(parts[1]) : ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError("The page in \(name) has no text to read.")
        }
        return ScreenPage(app: name, title: parts.first.map(String.init) ?? "", text: text)
    }
}
