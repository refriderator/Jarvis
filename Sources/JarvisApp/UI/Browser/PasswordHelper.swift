import JarvisKit
import WebKit

/// Saves and fills passwords for one web view. A script watches sign-in forms in a content world of its own, so
/// the page's scripts can neither see it nor call it. Which site a message came from is WebKit's own record of
/// the frame (`securityOrigin`), never something the page says. A password is only ever filled into the exact
/// host it was saved for, and only when a sign-in field is clicked into.
/// When anything about the page isn't clearly safe (see `safe`), nothing is offered, saved or filled.
@MainActor
final class PasswordHelper: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "JarvisPasswords")
    private static let handler = "jarvisPasswords"

    /// A submitted sign-in that isn't saved yet: the Web tab asks whether to save it.
    private let offer: (SavedLogin) -> Void
    /// Usernames typed on a step before the password (Google asks for the email, then the password).
    private var usernames: [String: String] = [:]

    init(offer: @escaping (SavedLogin) -> Void) {
        self.offer = offer
    }

    func install(on configuration: WKWebViewConfiguration) {
        let script = WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: Self.world)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(self, contentWorld: Self.world, name: Self.handler)
    }

    /// The web view keeps its message handler alive; this lets the page go.
    func uninstall(from view: WKWebView) {
        view.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard let view = message.webView, safe(origin, view: view), let body = message.body as? [String: Any],
              let kind = body["kind"] as? String, body["optedOut"] as? Bool != true else { return }
        let host = origin.host
        let username = (body["username"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        switch kind {
        case "username":
            if !username.isEmpty { usernames[host] = username }
        case "save":
            guard let password = body["password"] as? String, !password.isEmpty else { return }
            let login = SavedLogin(host: host, username: username.isEmpty ? usernames[host] ?? "" : username, password: password)
            if !PasswordStore.logins(for: host).contains(login) { offer(login) }
        case "fill":
            let saved = PasswordStore.logins(for: host)
            guard let login = saved.first(where: { $0.username == usernames[host] }) ?? saved.first else { return }
            view.callAsyncJavaScript("window.__jarvisFill(username, password)",
                                                 arguments: ["username": login.username, "password": login.password],
                                                 in: message.frameInfo, in: Self.world) { _ in }
        default:
            break
        }
    }

    /// Safe for anyone: https on a public website (`PasswordSafety`), every part of the page loaded securely (no
    /// mixed content), the site's certificate checked, and the form on the page's own site, not in a frame from
    /// somewhere else (an ad, an embed).
    private func safe(_ origin: WKSecurityOrigin, view: WKWebView) -> Bool {
        origin.protocol == "https" && PasswordSafety.allows(host: origin.host, port: origin.port)
            && view.hasOnlySecureContent && view.serverTrust != nil
            && view.url?.scheme == "https" && view.url?.host(percentEncoded: false)?.lowercased() == origin.host.lowercased()
    }

    /// Finds the visible sign-in fields; on submit (a form, a button, Enter) sends what's in them; on clicking into
    /// one asks for a saved sign-in; fills it the way typing would, so sites built on React and the like notice.
    private static let script = """
    (() => {
      const post = (message) => window.webkit.messageHandlers.\(handler).postMessage(message);
      const shown = (el) => el.getClientRects().length > 0;
      const isPassword = (el) => el instanceof HTMLInputElement && el.type === 'password';
      const isUser = (el) => el instanceof HTMLInputElement && ['email', 'text', 'tel'].includes(el.type) &&
        /user|email|login|account|identifier/i.test([el.autocomplete, el.name, el.id, el.getAttribute('aria-label')].join(' '));
      const fields = () => {
        const inputs = [...document.querySelectorAll('input')].filter(shown);
        return { passwords: inputs.filter(isPassword), users: inputs.filter(isUser) };
      };
      let sent = '';
      // A site that asks browsers not to remember its password (autocomplete="off") is left alone.
      const optedOut = (passwords) => passwords.some((el) =>
        el.autocomplete === 'off' || (el.form && el.form.getAttribute('autocomplete') === 'off'));
      const capture = () => {
        const { passwords, users } = fields();
        if (optedOut(passwords)) return;
        const password = passwords.map((el) => el.value).find((value) => value);
        const username = users.map((el) => el.value).find((value) => value) || '';
        if (password) {
          if (username + '\\n' + password === sent) return;
          sent = username + '\\n' + password;
          post({ kind: 'save', username, password });
        } else if (username) {
          post({ kind: 'username', username });
        }
      };
      document.addEventListener('submit', capture, true);
      document.addEventListener('click', (event) => {
        if (event.target instanceof Element && event.target.closest('button, input[type=submit], [role=button]')) capture();
      }, true);
      document.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && (isPassword(event.target) || isUser(event.target))) capture();
      }, true);
      window.addEventListener('pagehide', capture, true);
      document.addEventListener('focusin', (event) => {
        if (isPassword(event.target) || isUser(event.target)) post({ kind: 'fill', optedOut: optedOut(fields().passwords) });
      }, true);
      window.__jarvisFill = (username, password) => {
        const set = (el, value) => {
          Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        };
        const { passwords, users } = fields();
        if (passwords[0] && !passwords[0].value) set(passwords[0], password);
        if (users[0] && !users[0].value && username) set(users[0], username);
      };
    })();
    """
}
