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
/// windows, opening to a 2 × 3 grid of them with their empty places. Beside a hardware notch the dot's tab sits on
/// the notch's right like the apps' tab beside the notch. A window dragged over it shows its app's icon in the next
/// empty place. Drawn where it is on screen inside its window, which covers every stage (`TrayLayout.bounds`).
struct TrayView: View {
    let model: TrayModel
    let state: AppState
    let dock: DockController
    /// Moving to another display: the tab beside a hardware notch is in behind it (`NotchHop`).
    @Environment(\.tabsTucked) private var tucked

    /// The stage drawn. It follows the model's, in two steps where the shape changes (`follow`).
    @State private var shown: TrayStage = .hidden
    /// The open grid folded up to nothing behind the hardware notch, on its way to or from the side tab.
    @State private var folded = false
    /// Counts `follow`'s changes, so a step left over from an earlier one is dropped.
    @State private var steps = 0

    /// What shows: resting beside a hardware notch, it's tucked in behind it while the notch moves display.
    private var stage: TrayStage {
        tucked && shown == .dot && model.layout.isBeside(.dot) ? .hidden : shown
    }

    private var frame: CGRect {
        let open = model.layout.frame(for: .open)
        return folded ? CGRect(x: open.minX, y: open.maxY, width: open.width, height: 0) : model.layout.frame(for: stage)
    }

    var body: some View {
        let layout = model.layout
        let frame = frame
        // The window's top-left corner on screen (see `ScreenTrays.panelFrame`).
        let origin = CGPoint(x: layout.bounds.minX - ScreenTrays.glowRoom, y: layout.bounds.maxY)
        let skin = state.skin
        tray
            .frame(width: frame.width, height: frame.height, alignment: layout.isBeside(stage) ? .trailing : .top)
            .clipped()
            // Glows as one shape, outside the clip: inside it, the glow was cut into a square-cornered box, and on
            // the ZStack each icon and empty place got a halo of its own.
            .compositingGroup()
            .shadow(color: skin.accent.opacity(stage == .open && skin.material != .glass ? 0.7 : 0), radius: skin.glow)
            .scaleEffect(model.catching ? 1.05 : 1, anchor: .top)
            .offset(x: frame.minX - origin.x, y: origin.y - frame.maxY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Self.spring, value: tucked)
            .animation(.spring(duration: 0.25), value: model.catching)
            .animation(.spring(duration: 0.35, bounce: 0.3), value: model.apps)
            .onChange(of: model.stage, initial: true) { _, new in follow(new) }
    }

    private static let spring = Animation.spring(duration: 0.4, bounce: 0.25)

    /// Goes to `new`. Beside a hardware notch the grid hangs below it and the dot's tab sits on its right, so one
    /// goes in before the other comes out: the grid folds up behind the notch, then the tab springs out; the tab
    /// slides in, then the grid drops. Morphed in one go, the two shapes slid across each other.
    private func follow(_ new: TrayStage) {
        steps += 1
        let step = steps
        let layout = model.layout
        guard layout.hardwareNotch != nil, layout.isBeside(shown) != layout.isBeside(new) else {
            return withAnimation(Self.spring) { shown = new }
        }
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        if shown == .open {
            withAnimation(.easeIn(duration: 0.16)) { folded = true } completion: {
                guard step == steps else { return }
                withTransaction(instant) {
                    folded = false
                    shown = .hidden
                }
                if new != .hidden { withAnimation(Self.spring) { shown = new } }
            }
        } else {
            withAnimation(.easeIn(duration: 0.14)) { shown = .hidden } completion: {
                guard step == steps else { return }
                withTransaction(instant) {
                    shown = .open
                    folded = true
                }
                withAnimation(Self.spring) { folded = false }
            }
        }
    }

    @ViewBuilder
    private var tray: some View {
        let skin = state.skin
        if model.layout.isBeside(stage) {
            ZStack(alignment: .trailing) {
                surface(DockTabShape(), border: DockTabShape(outerOnly: true), skin: skin)
                if stage == .dot {
                    dot
                        .frame(width: TrayLayout.besideOut - DockTabShape.flare)
                        // A point in from the middle of what shows, which looked too far right.
                        .padding(.trailing, DockTabShape.flare + 1)
                        .transition(.opacity)
                }
            }
        } else {
            let radius: CGFloat = stage == .open ? 16 : 9
            ZStack(alignment: .top) {
                surface(NotchShape(radius: radius, shoulder: 6), border: NotchShape(radius: radius, shoulder: 6, openTop: true),
                        skin: skin)
                if stage == .open {
                    grid(skin: skin).transition(.opacity)
                } else if stage == .dot {
                    dot.frame(height: model.layout.menuBarHeight).transition(.opacity)
                }
            }
        }
    }

    private var dot: some View {
        Circle().fill(.white).frame(width: 5, height: 5)
    }

    @ViewBuilder
    private func surface<S: Shape, B: Shape>(_ shape: S, border: B, skin: Skin) -> some View {
        if skin.material == .glass {
            Color.clear.glass(tint: skin.background.opacity(skin.glassDarkness), in: shape)
                .overlay { inside(border, of: shape, color: skin.foreground.opacity(0.34), width: 0.8) }
        } else {
            shape.fill(skin.background.opacity(skin.backgroundOpacity))
                .overlay { if let line = skin.border { inside(border, of: shape, color: line, width: skin.borderWidth) } }
        }
    }

    /// The border all inside the tray, its outer edge on the fill's: stroked twice as wide and clipped to the
    /// shape. Centred on the edge it lost its outer half to the clip (or showed below a hardware notch); moved in by
    /// half its width, its corners came off the fill's, which showed outside it.
    private func inside<B: Shape, S: Shape>(_ border: B, of shape: S, color: Color, width: CGFloat) -> some View {
        border.stroke(color, lineWidth: 2 * width).clipShape(shape)
    }

    /// Three columns, two rows: the held windows' icons, then the places left. A window being dragged over it
    /// fades into the first place left.
    private func grid(skin: Skin) -> some View {
        let columns = Array(repeating: GridItem(.fixed(TrayLayout.slot.width), spacing: 0), count: TrayLayout.columns)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<NotchDock.maxApps, id: \.self) { index in
                Group {
                    if index < model.apps.count {
                        held(model.apps[index], size: 30)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 30 / 4)
                                .strokeBorder(skin.foreground.opacity(model.catching ? 0.7 : 0.28),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            if index == model.apps.count, let icon = dock.draggedIcon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 26, height: 26)
                                    .opacity(model.catching ? 1 : 0)
                                    .scaleEffect(model.catching ? 1 : 0.6)
                            }
                        }
                        .frame(width: 30, height: 30)
                    }
                }
                .frame(width: TrayLayout.slot.width, height: TrayLayout.slot.height)
            }
        }
        .frame(width: TrayLayout.slot.width * CGFloat(TrayLayout.columns))
        .padding(.top, model.layout.hangsFrom)
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
