import AppKit
import JarvisKit
import SwiftUI

@MainActor
@Observable
final class TrayModel {
    let layout: TrayLayout
    var apps: [HeldApp] = []
    var stage: TrayStage = .hidden
    /// A window dragged over it would be held here if let go.
    var catching = false

    init(layout: TrayLayout) {
        self.layout = layout
    }
}

/// A display's tray (`ScreenTrays`), in the skin like the notch: a small notch with a white dot while it holds
/// windows, opening to a 2 × 3 grid of them with their empty places. Beside a hardware notch it grows sideways
/// out from under it instead of down.
struct TrayView: View {
    let model: TrayModel
    let state: AppState
    let dock: DockController

    private var beside: Bool { model.layout.hardwareNotch != nil }

    var body: some View {
        let size = model.layout.frame(for: model.stage).size
        tray
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .scaleEffect(model.catching ? 1.05 : 1, anchor: .top)
            .padding(.horizontal, ScreenTrays.glowRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: beside ? .topLeading : .top)
            .animation(.spring(duration: 0.4, bounce: 0.25), value: model.stage)
            .animation(.spring(duration: 0.25), value: model.catching)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: model.apps)
    }

    @ViewBuilder
    private var tray: some View {
        let skin = state.skin
        let glows = model.stage == .open && skin.material != .glass
        ZStack(alignment: beside ? .trailing : .top) {
            if beside {
                surface(DockTabShape(), border: DockTabShape(outerOnly: true), skin: skin)
            } else {
                let radius: CGFloat = model.stage == .open ? 16 : 9
                surface(NotchShape(radius: radius, shoulder: 6), border: NotchShape(radius: radius, shoulder: 6, openTop: true),
                        skin: skin)
            }
            if model.stage == .open {
                grid(skin: skin).transition(.opacity)
            } else if model.stage == .dot {
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .frame(width: beside ? TrayLayout.besideDot : nil, height: model.layout.menuBarHeight)
                    .padding(.trailing, beside ? 2 : 0)
                    .transition(.opacity)
            }
        }
        .shadow(color: skin.accent.opacity(glows ? 0.7 : 0), radius: skin.glow)
    }

    @ViewBuilder
    private func surface<S: Shape, B: Shape>(_ shape: S, border: B, skin: Skin) -> some View {
        if skin.material == .glass {
            Color.clear.glass(tint: skin.background.opacity(skin.glassDarkness), in: shape)
                .overlay { border.stroke(skin.foreground.opacity(0.34), lineWidth: 0.8) }
        } else {
            shape.fill(skin.background.opacity(skin.backgroundOpacity))
                .overlay { if let line = skin.border { border.stroke(line, lineWidth: skin.borderWidth) } }
        }
    }

    /// Three columns, two rows: the held windows' icons, then the places left.
    private func grid(skin: Skin) -> some View {
        let notch = model.layout.hardwareNotch?.height ?? 0
        let cell = beside ? CGSize(width: TrayLayout.besideSlot, height: notch / 2)
                          : TrayLayout.slot
        let icon = beside ? notch / 2 - 3 : 30
        // Rows first, so the icons read left to right.
        let columns = Array(repeating: GridItem(.fixed(cell.width), spacing: 0), count: TrayLayout.columns)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<NotchDock.maxApps, id: \.self) { index in
                Group {
                    if index < model.apps.count {
                        held(model.apps[index], size: icon)
                    } else {
                        RoundedRectangle(cornerRadius: icon / 4)
                            .strokeBorder(skin.foreground.opacity(model.catching ? 0.7 : 0.28),
                                          style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: icon, height: icon)
                    }
                }
                .frame(width: cell.width, height: cell.height)
            }
        }
        .frame(width: cell.width * CGFloat(TrayLayout.columns))
        .padding(.top, beside ? 0 : model.layout.menuBarHeight)
        .padding(.trailing, beside ? TrayLayout.besideEnd : 0)
    }

    private func held(_ app: HeldApp, size: CGFloat) -> some View {
        let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage()
        return Image(nsImage: icon)
            .resizable()
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .help("\(app.appName): click to open it full desktop, drag it out to hold it, right-click to let go of it")
            .onTapGesture { dock.restore(app) }
            .contextMenu { Button("Let Go") { dock.letGo(app) } }
            .gesture(DragGesture(minimumDistance: 3).onChanged { _ in dock.pullOut(app, icon: icon) })
    }
}
