import AppKit
import JarvisKit
import SwiftUI

/// Displays without the notch get their own strip: a small tab hanging from the middle of the menu bar with the
/// icons of the windows set aside on the desktop that display is showing. It works like the notch's tab: click
/// an icon to bring its window back filling the desktop, drag it out to carry the window. Only there while it
/// holds something.
@MainActor
final class ScreenTrays {
    private let state: AppState
    private let dock: DockController
    private var trays: [CGDirectDisplayID: Tray] = [:]
    private var observers: [NSObjectProtocol] = []

    private struct Tray {
        let panel: NotchPanel
        let model: TrayModel
        let screen: NSScreen
    }

    init(state: AppState, dock: DockController) {
        self.state = state
        self.dock = dock
        rebuild()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuild() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observeApps()
    }

    private func observeApps() {
        withObservationTracking {
            _ = state.dock.apps
            _ = state.skin.id
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeApps()
            }
        }
    }

    private func rebuild() {
        trays.values.forEach { $0.panel.orderOut(nil) }
        trays = [:]
        let notched = NSScreen.menuBarScreen
        for screen in NSScreen.screens where screen != notched {
            guard let id = screen.displayID else { continue }
            let model = TrayModel()
            let panel = NotchPanel()
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: TrayView(model: model, state: state, dock: dock))
            trays[id] = Tray(panel: panel, model: model, screen: screen)
        }
        refresh()
    }

    /// Each tray shows its display's desktop's held apps, sized to them, and hides when there are none.
    private func refresh() {
        for (id, tray) in trays {
            let desktop = Desktops.active(on: id)
            let apps = state.dock.apps.filter { $0.desktop != nil && $0.desktop == desktop }
            tray.model.apps = apps
            guard !apps.isEmpty else {
                tray.panel.orderOut(nil)
                continue
            }
            let frame = tray.screen.frame
            let menuBar = frame.maxY - tray.screen.visibleFrame.maxY
            let height = menuBar > 4 ? menuBar : 24
            tray.model.height = height
            let width = TrayView.width(for: apps.count)
            tray.panel.setFrame(CGRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height),
                                display: true)
            tray.panel.orderFrontRegardless()
        }
    }
}

@MainActor
@Observable
final class TrayModel {
    var apps: [HeldApp] = []
    var height: CGFloat = 24
}

/// The tray: flat along the top of the screen, rounded below, in the skin's colours, icons in a row.
private struct TrayView: View {
    let model: TrayModel
    let state: AppState
    let dock: DockController

    static let slot: CGFloat = 26

    static func width(for count: Int) -> CGFloat { 12 + CGFloat(count) * slot }

    var body: some View {
        let skin = state.skin
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
        HStack(spacing: 0) {
            ForEach(model.apps) { app in
                let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage()
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .frame(width: Self.slot, height: model.height)
                    .contentShape(Rectangle())
                    .help("\(app.appName): click to open it full screen, or drag it out")
                    .onTapGesture { dock.restore(app) }
                    .gesture(DragGesture(minimumDistance: 3).onChanged { _ in dock.pullOut(app, icon: icon) })
            }
        }
        .padding(.horizontal, 6)
        .frame(width: Self.width(for: model.apps.count), height: model.height)
        .background(skin.background.opacity(skin.material == .glass ? 0.85 : skin.backgroundOpacity), in: shape)
        .overlay { if let border = skin.border { shape.strokeBorder(border, lineWidth: 1) } }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: model.apps)
    }
}
