import JarvisKit
import SwiftUI
import WebKit

/// The Web tab: back and forward, the tabs (click to show, x to close, drag to reorder), a new-tab button, the
/// address field and the size toggle (the Finder tab's depth, or as deep as Large's video). A tab with no page
/// shows the start page: the bookmarks.
struct BrowserView: View {
    let state: AppState
    let browser: BrowserController
    @State private var address = ""
    @FocusState private var typing: Bool
    @State private var draggingTab: BrowserTab.ID?
    /// The pointer is on the address field: the open-in-your-browser arrow shows at its left end.
    @State private var onAddress = false

    var body: some View {
        let tint = state.skin.foreground
        VStack(spacing: 6) {
            toolbar(tint: tint)
            if let offer = browser.passwordOffer {
                PasswordOfferBar(login: offer, tint: tint, accent: state.skin.accent, browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Group {
                if let page = browser.current {
                    WebPageView(view: page.view)
                } else {
                    StartPage(browser: browser, tint: tint, accent: state.skin.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tint.opacity(state.skin.surface), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let edge = state.skin.surfaceEdge {
                RoundedRectangle(cornerRadius: 12).strokeBorder(edge, lineWidth: 1)
            }
        }
        .background {
            // Zoom the page, like a browser.
            Group {
                Button("") { browser.zoom(by: 0.1) }.keyboardShortcut("=", modifiers: .command)
                Button("") { browser.zoom(by: -0.1) }.keyboardShortcut("-", modifiers: .command)
                Button("") { browser.zoom(by: nil) }.keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        // The field shows where the tab is, except while it's being typed in.
        .onChange(of: browser.tabs.current) { if !typing { address = browser.tabs.current.url?.absoluteString ?? "" } }
        .onAppear { address = browser.tabs.current.url?.absoluteString ?? "" }
    }

    private func toolbar(tint: Color) -> some View {
        HStack(spacing: 6) {
            icon("chevron.left", help: "Back", tint: tint, enabled: browser.canGoBack, action: browser.back)
            icon("chevron.right", help: "Forward", tint: tint, enabled: browser.canGoForward, action: browser.forward)
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(browser.tabs.tabs) { tab in
                        TabChip(tab: tab, on: tab.id == browser.tabs.selected, tint: tint, accent: state.skin.accent,
                                select: { browser.select(tab.id) }, close: { browser.close(tab.id) })
                            .reorderable(tab.id, dragging: $draggingTab, move: browser.move)
                    }
                }
            }
            .scrollIndicators(.never)
            .endsReorder(dragging: $draggingTab)
            icon("plus", help: "New tab", tint: tint, action: browser.newTab)
            HStack(spacing: 2) {
                // Hovered, a page showing: open it in the default browser (Safari, Chrome...).
                if onAddress, !typing, let url = browser.current?.view.url ?? browser.tabs.current.url {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption.weight(.semibold))
                            .frame(width: 16, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tint.opacity(0.8))
                    .help("Open in your browser")
                    .transition(.opacity)
                }
                TextField("Search or address", text: $address)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($typing)
                    .onSubmit { browser.go(typed: address); typing = false }
            }
            .padding(.leading, onAddress && !typing && browser.tabs.current.url != nil ? 4 : 8)
            .padding(.trailing, 8)
            .frame(width: 170, height: 22)
            .background(tint.opacity(0.08), in: Capsule())
            .onHover { onAddress = $0 }
            .animation(.easeInOut(duration: 0.15), value: onAddress)
            icon(state.dock.browserLarge ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                 help: state.dock.browserLarge ? "Smaller" : "Larger", tint: tint, action: browser.toggleLarge)
        }
        .frame(height: 22)
    }

    private func icon(_ name: String, help: String, tint: Color, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint.opacity(enabled ? 0.8 : 0.25))
        .disabled(!enabled)
        .help(help)
    }
}

/// "Save password for site?" under the toolbar, after a sign-in that isn't saved yet.
private struct PasswordOfferBar: View {
    let login: SavedLogin
    let tint: Color
    let accent: Color
    let browser: BrowserController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(accent)
            Text("Save password for \(login.host)\(login.username.isEmpty ? "" : " (\(login.username))")?")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button("Never for this site", action: browser.neverSavePassword)
            Button("Not now", action: browser.dismissPasswordOffer)
            Button("Save", action: browser.savePassword).keyboardShortcut(.defaultAction)
        }
        .font(.caption)
        .controlSize(.small)
        .foregroundStyle(tint.opacity(0.85))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// One tab in the strip: its page's title, and an x to close it.
private struct TabChip: View {
    let tab: BrowserTab
    let on: Bool
    let tint: Color
    let accent: Color
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.label)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close tab")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 22)
        .foregroundStyle(on ? accent : tint.opacity(0.65))
        .background(on ? accent.opacity(0.2) : tint.opacity(0.06), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: select)
    }
}

/// Shows the tab's web view (kept by the controller, so it's never reloaded) in a holder that swaps it for
/// another tab's: SwiftUI keeps one holder across tabs, and handing it the first tab's view for good left every
/// tab showing that page.
struct WebPageView: NSViewRepresentable {
    let view: PanelWebView

    func makeNSView(context: Context) -> NSView {
        let holder = NSView()
        show(in: holder)
        return holder
    }

    func updateNSView(_ holder: NSView, context: Context) {
        if holder.subviews.first !== view { show(in: holder) }
    }

    private func show(in holder: NSView) {
        holder.subviews.forEach { $0.removeFromSuperview() }
        view.frame = holder.bounds
        view.autoresizingMask = [.width, .height]
        holder.addSubview(view)
    }
}
