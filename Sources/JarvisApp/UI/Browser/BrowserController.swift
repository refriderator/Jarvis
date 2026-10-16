import JarvisKit
import Observation
import WebKit

/// The Web tab's browser: its tabs, and a live web view for each tab showing a page. The pages stay loaded while
/// Jarvis runs, so switching tabs (or closing the notch) never reloads them.
@MainActor @Observable
final class BrowserController {
    private let state: AppState
    private(set) var tabs = BrowserTabs()
    @ObservationIgnored private var pages: [BrowserTab.ID: BrowserPage] = [:]
    /// A sign-in just submitted that isn't saved: the Web tab asks whether to save it.
    private(set) var passwordOffer: SavedLogin?

    init(state: AppState) {
        self.state = state
    }

    /// The web view for the tab showing; nil on its start page.
    var current: BrowserPage? { tabs.current.url == nil ? nil : page(for: tabs.current.id) }

    func go(to url: URL) {
        let id = tabs.current.id
        tabs.update(id, url: url, title: "")
        page(for: id).load(url)
    }

    /// The address field: an address, or a web search.
    func go(typed: String) {
        if let url = BrowserTabs.address(typed) { go(to: url) }
    }

    func newTab() { tabs.open(); fullscreenChanged() }
    func select(_ id: BrowserTab.ID) { tabs.select(id); fullscreenChanged() }

    /// Pauses every video in every tab.
    func pauseVideos() {
        for page in pages.values {
            page.view.evaluateJavaScript("document.querySelectorAll('video').forEach((video) => video.pause())")
        }
    }

    /// Takes the tab showing out of full screen (`PageFullscreen`'s own, in the page's world).
    func leaveFullscreen() {
        current?.view.evaluateJavaScript("document.fullscreenElement && document.exitFullscreen()")
    }

    /// Whether the tab showing has a video full screen, for the closed notch's medium player.
    private func fullscreenChanged() {
        let on = current?.fullscreen ?? false
        if state.dock.browserFullscreen != on { state.updateDock { $0.browserFullscreen = on } }
    }
    func move(_ id: BrowserTab.ID, to target: BrowserTab.ID) { tabs.move(id, to: target) }

    func close(_ id: BrowserTab.ID) {
        pages.removeValue(forKey: id)?.stop()
        tabs.close(id)
        fullscreenChanged()
    }

    /// Back from the first page goes to the start page; forward from there goes to the page again.
    func back() {
        if let page = current, page.canGoBack { page.view.goBack() } else if current != nil { showStart() }
    }

    func forward() {
        if current == nil, let page = pages[tabs.current.id], page.view.url != nil {
            tabs.update(tabs.current.id, url: page.view.url, title: page.title)
        } else {
            current?.view.goForward()
        }
    }

    /// ⌘− / ⌘= / ⌘0 on the page showing; nil puts it back to the starting zoom.
    func zoom(by step: Double?) {
        guard let view = current?.view else { return }
        view.zoomStep = step.map { view.zoomStep + $0 } ?? 0
    }

    var canGoBack: Bool { current != nil }
    var canGoForward: Bool { current?.canGoForward ?? (pages[tabs.current.id]?.view.url != nil) }

    private func showStart() {
        tabs.update(tabs.current.id, url: nil, title: "")
        fullscreenChanged()
    }

    private func page(for id: BrowserTab.ID) -> BrowserPage {
        if let page = pages[id] { return page }
        let page = BrowserPage { [weak self] url, title in
            // Only while it's showing a page: on the start page, the web view behind it is kept for Forward.
            guard let self, tabs.tabs.first(where: { $0.id == id })?.url != nil else { return }
            tabs.update(id, url: url, title: title)
        } openInNewTab: { [weak self] url in
            self?.tabs.open(url)
            self?.go(to: url)
        } fullscreen: { [weak self] in
            self?.fullscreenChanged()
        } offerPassword: { [weak self] login in
            guard let self, !state.settings.passwordNeverSave.contains(login.host) else { return }
            passwordOffer = login
        }
        pages[id] = page
        return page
    }

    // MARK: Saving passwords

    func savePassword() {
        if let passwordOffer { PasswordStore.save(passwordOffer) }
        passwordOffer = nil
    }

    func neverSavePassword() {
        if let host = passwordOffer?.host { state.update { $0.passwordNeverSave.append(host) } }
        passwordOffer = nil
    }

    func dismissPasswordOffer() { passwordOffer = nil }

    // MARK: Bookmarks (the start page)

    var bookmarks: [Bookmark] { state.settings.bookmarks }

    func addBookmark(name: String, typed: String) {
        guard let url = BrowserTabs.address(typed) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        state.update { $0.bookmarks.append(Bookmark(name: trimmed.isEmpty ? url.host() ?? typed : trimmed, url: url)) }
    }

    /// Drag-to-reorder on the start page: it goes where `target` is, the others shifting to make room.
    func moveBookmark(_ id: Bookmark.ID, to target: Bookmark.ID) {
        state.update { settings in
            guard id != target, let from = settings.bookmarks.firstIndex(where: { $0.id == id }),
                  let to = settings.bookmarks.firstIndex(where: { $0.id == target }) else { return }
            settings.bookmarks.insert(settings.bookmarks.remove(at: from), at: to)
        }
    }

    func removeBookmark(_ bookmark: Bookmark) {
        state.update { $0.bookmarks.removeAll { $0.id == bookmark.id } }
    }

    func toggleLarge() {
        state.updateDock { $0.browserLarge.toggle() }
    }
}

/// One tab's web view, and what the toolbar needs to know about it.
@MainActor @Observable
final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    @ObservationIgnored let view: PanelWebView
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var title = ""
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []
    @ObservationIgnored private let changed: (URL?, String) -> Void
    @ObservationIgnored private let openInNewTab: (URL) -> Void
    @ObservationIgnored private let passwords: PasswordHelper

    /// A video in the page is full screen (`PageFullscreen`).
    private(set) var fullscreen = false
    @ObservationIgnored private let fullscreenWatch = PageFullscreen()

    init(changed: @escaping (URL?, String) -> Void, openInNewTab: @escaping (URL) -> Void,
         fullscreen: @escaping () -> Void, offerPassword: @escaping (SavedLogin) -> Void) {
        let configuration = WKWebViewConfiguration()
        // The system's full screen stays off (it took over the whole screen); pages get Jarvis's own instead.
        fullscreenWatch.install(on: configuration)
        passwords = PasswordHelper(offer: offerPassword)
        passwords.install(on: configuration)
        configuration.websiteDataStore = .default()   // cookies kept, like a normal browser
        // Said to be Safari, the version installed: without it, sites (Google's especially) see an unknown browser
        // and call it out of date.
        configuration.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        view = PanelWebView(frame: .zero, configuration: configuration)
        self.changed = changed
        self.openInNewTab = openInNewTab
        super.init()
        fullscreenWatch.changed = { [weak self] on in
            self?.fullscreen = on
            fullscreen()
        }
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        watching = [
            view.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            view.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
            view.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.report(view) } },
            view.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.report(view) } },
        ]
    }

    /// The Safari on this Mac, for the user agent.
    private static let safariVersion = Bundle(path: "/Applications/Safari.app")?
        .infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.0"

    func load(_ url: URL) {
        view.load(URLRequest(url: url))
    }

    func stop() {
        view.stopLoading()
        passwords.uninstall(from: view)   // also drops the full-screen handler
        watching = []
    }

    private func report(_ view: WKWebView) {
        title = view.title ?? ""
        changed(view.url, title)
    }

    // Links that would open a new window (target="_blank", window.open) open in a new tab instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { openInNewTab(url) }
        return nil
    }
}

/// The panel only takes the keyboard for views that ask for it (`becomesKeyOnlyIfNeeded`); a web page always may
/// need typing in, so a click on it does.
/// Zoomed out to fit: pages are written for a laptop-wide window, and at the notch's width they'd switch to big
/// text and full-width sidebars. Scaled so the page is laid out `desktopWidth` wide, whatever size the tab is.
final class PanelWebView: WKWebView {
    static let desktopWidth: CGFloat = 1100
    /// ⌘− / ⌘= on top of the fitted zoom; ⌘0 sets it back to 0.
    var zoomStep = 0.0 { didSet { fit() } }

    override var needsPanelToBecomeKey: Bool { true }

    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        fit()
    }

    private func fit() {
        guard bounds.width > 0 else { return }
        let fitted = min(0.85, max(0.5, bounds.width / Self.desktopWidth))
        pageZoom = min(2, max(0.3, fitted + zoomStep))
    }
}
