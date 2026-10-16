import WebKit

/// Full screen that stays inside the Web tab. The system's own full screen is off (it took over the whole screen),
/// and with it off sites like YouTube grey out their full-screen button. So the page is given a full-screen API of
/// Jarvis's own: asking for full screen makes the video's player fill the Web tab with the rest of the page hidden
/// (with the large size toggle, as big as the notch gets), and leaving puts it back. Both the standard calls and
/// Safari's `webkit` ones, since sites check for either. Checked against YouTube in a test web view: plays full
/// size, and the button leaves again.
/// It has to run in the page's own world, so the page can see it; it only restyles the page's own elements.
/// Jarvis is told when the main page goes in or out of full screen, for the closed notch's medium player. The page
/// could fake that message, but all it changes is whether the notch shows the page small.
@MainActor
final class PageFullscreen: NSObject, WKScriptMessageHandler {
    var changed: (Bool) -> Void = { _ in }

    func install(on configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        configuration.userContentController.add(self, contentWorld: .page, name: "jarvisFullscreen")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let on = message.body as? Bool else { return }
        changed(on)
    }

    private static let script = """
    (() => {
      let current = null;   // what the page asked to show full screen, which is what it's told is full screen
      let shown = null;     // what actually fills the view (see `target`)
      const style = document.createElement('style');
      style.textContent = `
        .jarvis-fullscreen { position: fixed !important; inset: 0 !important; width: 100vw !important;
          height: 100vh !important; max-width: none !important; max-height: none !important; margin: 0 !important;
          z-index: 2147483647 !important; background: #000 !important; transform: none !important; }
        video.jarvis-fullscreen { object-fit: contain !important; }
        html.jarvis-fullscreen-on, html.jarvis-fullscreen-on body { overflow: hidden !important; }
        html.jarvis-fullscreen-on body * { visibility: hidden !important; }
        html.jarvis-fullscreen-on .jarvis-fullscreen, html.jarvis-fullscreen-on .jarvis-fullscreen * {
          visibility: visible !important; }`;
      const changed = (element) => {
        for (const name of ['fullscreenchange', 'webkitfullscreenchange']) {
          element.dispatchEvent(new Event(name, { bubbles: true }));
        }
        window.dispatchEvent(new Event('resize'));
        if (window === top) window.webkit?.messageHandlers?.jarvisFullscreen?.postMessage(current !== null);
      };
      // Asked for the whole page (YouTube does): the player of the page's biggest video fills it instead, since
      // pinning the page itself changes nothing. The player is the video's nearest ancestor named like one, else
      // its parent.
      const target = (element) => {
        if (element !== document.documentElement && element !== document.body) return element;
        const area = (video) => { const box = video.getBoundingClientRect(); return box.width * box.height; };
        const video = [...document.querySelectorAll('video')].sort((a, b) => area(b) - area(a))[0];
        if (!video) return element;
        for (let node = video.parentElement; node && node !== document.body; node = node.parentElement) {
          if (/player/i.test(node.id + ' ' + node.className)) return node;
        }
        return video.parentElement || element;
      };
      const enter = function () {
        // Asked again for what's already full screen: a toggle (YouTube's button and F key work that way here,
        // since its player never learns it went full screen), so leave.
        if (current === this) return leave();
        if (current) leave();
        current = this;
        shown = target(this);
        if (!style.isConnected) (document.head || document.documentElement).appendChild(style);
        shown.classList.add('jarvis-fullscreen');
        document.documentElement.classList.add('jarvis-fullscreen-on');
        changed(current);
        return Promise.resolve();
      };
      const leave = () => {
        if (!current) return Promise.resolve();
        const element = current;
        shown.classList.remove('jarvis-fullscreen');
        document.documentElement.classList.remove('jarvis-fullscreen-on');
        current = shown = null;
        changed(element);
        return Promise.resolve();
      };
      const define = (target, names, value) => {
        for (const name of names) {
          try { Object.defineProperty(target, name, { configurable: true, ...value }); } catch (_) {}
        }
      };
      define(Element.prototype, ['requestFullscreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen'], { value: enter });
      define(HTMLVideoElement.prototype, ['webkitEnterFullscreen', 'webkitEnterFullScreen'], { value: enter });
      define(Document.prototype, ['exitFullscreen', 'webkitExitFullscreen', 'webkitCancelFullScreen'], { value: leave });
      define(HTMLVideoElement.prototype, ['webkitExitFullscreen', 'webkitExitFullScreen'], { value: leave });
      define(Document.prototype, ['fullscreenEnabled', 'webkitFullscreenEnabled', 'webkitFullScreenEnabled'],
             { get: () => true });
      define(Document.prototype, ['fullscreenElement', 'webkitFullscreenElement', 'webkitCurrentFullScreenElement'],
             { get: () => current });
      define(Document.prototype, ['webkitIsFullScreen', 'fullscreen'], { get: () => current !== null });
      define(HTMLVideoElement.prototype, ['webkitSupportsFullscreen'], { get: () => true });
      define(HTMLVideoElement.prototype, ['webkitDisplayingFullscreen'], { get() { return current === this; } });
      document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && current) leave(); }, true);
    })();
    """
}
