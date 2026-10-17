import JarvisKit
import SwiftUI

/// The tab beside the closed notch with held apps' icons. It springs out from behind the notch once the
/// dropdown has closed and tucks back in when it opens. Click an icon to get its window back; drag it out and
/// the app lifts into the pointer and becomes its window there. Over a tucked video it's in front of the video's
/// tab, along its top (see `TuckedVideoTab`).
struct DockTab: View {
    let state: AppState
    let dock: DockController
    let video: VideoController
    let stage: NotchStage

    var body: some View {
        GeometryReader { geo in
            let layout = state.layout
            let shown = stage == .idle && layout.showsTab && video.morph == nil
            // In front of a tucked video's tab, no glow: it would light up that tab under it like a seam.
            TabBody(skin: state.skin, shown: shown, width: layout.tabFrame.width + DockTabShape.flare,
                    glows: !state.video.tucked, height: layout.tabFrame.height) {
                HStack(spacing: 4) {
                    if state.video.available && !state.video.held {
                        // A video is floating: hold it here.
                        Image(systemName: "pip.enter")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(state.skin.accent)
                            .frame(width: NotchLayout.tabSlotWidth - 4, height: 20)
                            .contentShape(Rectangle())
                            .help("Hold the video in the notch")
                            .onTapGesture(perform: video.hold)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                    ForEach(state.dock.shownApps) { app in
                        let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage()
                        TabIcon(image: icon, number: state.dock.number(of: app), accent: state.skin.accent)
                            .help("\(app.appName): click to open it full desktop, drag it out to hold it, right-click to let go of it")
                            .onTapGesture { dock.restore(app) }
                            .contextMenu { Button("Let Go") { dock.letGo(app) } }
                            .gesture(DragGesture(minimumDistance: 3).onChanged { _ in dock.pullOut(app, icon: icon) })
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
            }
            .besideNotch(layout.tabFrame, layout: layout, out: shown, in: geo)
        }
        .animation(DockTab.resize, value: state.layout.tabSlots)
    }

    /// Icons coming and going: the tab grows or shrinks with this.
    static let resize = Animation.spring(duration: 0.35, bounce: 0.3)
}

extension View {
    /// A side tab placed at `frame` (screen coordinates), in a panel view centred on the notch. Cut at the frame's
    /// left edge, so it comes out from behind the notch rather than over it. Only that edge: right and down the
    /// glow fades out freely instead of stopping in a box. Below the notch it fades out to the left too: cut
    /// there, it hung under the tab as a column with a hard left edge. Only while the tab is `out`: hidden behind
    /// the notch, its bottom edge (a point lower than the notch's) showed below it.
    func besideNotch(_ frame: CGRect, layout: NotchLayout, out: Bool, in geo: GeometryProxy) -> some View {
        let width = frame.width + DockTabShape.flare + 8
        return self
            .frame(width: width, height: frame.height + 18, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Rectangle().padding(.trailing, -GlowMask.reach).padding(.bottom, -GlowMask.reach)
                    if out {
                        Rectangle()
                            .padding(.leading, -GlowMask.reach).padding(.trailing, -GlowMask.reach)
                            .padding(.bottom, -GlowMask.reach)
                            .padding(.top, layout.notch.height)
                    }
                }
            }
            .position(x: geo.size.width / 2 + frame.minX - layout.notch.midX + width / 2, y: (frame.height + 18) / 2 - 1)
    }
}

/// Where a dragged window goes: an empty dashed box in the dropdown that the window's app icon fades into
/// while the window is on it. Reports its frame so the controller can tell when the pointer is on it.
struct DropBox: View {
    let state: AppState
    let dock: DockController

    var body: some View {
        let accent = state.skin.accent
        let catching = state.dock.catching
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accent.opacity(catching ? 1 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .frame(width: 64, height: 64)
                if let icon = dock.draggedIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 46, height: 46)
                        .opacity(catching ? 1 : 0)
                        .scaleEffect(catching ? 1 : 0.6)
                }
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.skin.foreground.opacity(catching ? 0.9 : 0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(state.skin.foreground.opacity(catching ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 12))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { dock.boxMoved($0) }
        .onDisappear { dock.boxMoved(nil) }
        .animation(.easeOut(duration: 0.18), value: catching)
    }

    private var label: String {
        switch (state.dock.dragging, state.dock.catching) {
        case (.folder, true): "Let go to open the folder here"
        case (.folder, false): "Bring the window here to open its folder"
        case (_, true): "Let go to keep it beside the notch"
        default: "Bring the window here to keep it"
        }
    }
}

private struct TabIcon: View {
    let image: NSImage?
    var number: Int? = nil
    var accent: Color = .accentColor

    var body: some View {
        Image(nsImage: image ?? NSImage())
            .resizable()
            .frame(width: 20, height: 20)
            .overlay(alignment: .bottomTrailing) { if let number { NumberBadge(number: number, accent: accent, size: 10) } }
            .frame(width: NotchLayout.tabSlotWidth - 4)
            .contentShape(Rectangle())
    }
}

/// Tells two held windows of the same app apart: a small number on the icon's corner.
struct NumberBadge: View {
    let number: Int
    let accent: Color
    let size: CGFloat

    var body: some View {
        Text("\(number)")
            .font(.system(size: size * 0.75, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size + 2, height: size + 2)
            .background(accent, in: Circle())
            .offset(x: size * 0.3, y: size * 0.3)
    }
}

struct TabBody<Content: View>: View {
    let skin: Skin
    let shown: Bool
    let width: CGFloat
    var bounce = true
    var glows = true
    var notchHeight: CGFloat? = nil
    var height: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        let shape = DockTabShape()
        ZStack(alignment: .trailing) {
            if skin.material == .glass {
                Color.clear.glass(tint: skin.background.opacity(skin.glassDarkness), in: shape)
            } else {
                shape.fill(skin.background.opacity(skin.backgroundOpacity))
            }
            if let border = skin.border {
                DockTabShape(outerOnly: true, leftEdgeTo: notchHeight).stroke(border, lineWidth: skin.borderWidth)
            }
            content
                .padding(.trailing, DockTabShape.flare + 4)
                .scaleEffect(shown ? 1 : 0.4, anchor: .trailing)
        }
        .frame(width: width, height: height)
        // Glows like the notch it hangs from.
        .shadow(color: skin.material == .glass || !glows ? .clear : skin.accent.opacity(shown ? 0.7 : 0), radius: skin.glow)
        // Hidden: pulled left, behind the notch and out of the clip.
        .offset(x: shown ? 0 : -width)
        .animation(Self.motion(shown: shown, bounce: bounce), value: shown)
    }

    /// Springing out (or appearing in place, without `bounce`) and sliding back in.
    static func motion(shown: Bool, bounce: Bool = true) -> Animation? {
        shown ? (bounce ? NotchMotion.tabBounce : nil) : NotchMotion.tabIn
    }
}

/// The tab: its left side hides under the notch, the top right flares into the menu bar like the notch's
/// shoulders, and the bottom right is rounded.
struct DockTabShape: Shape {
    static let flare: CGFloat = 6
    /// Only the outer edges, for the border: the left and top ones run under the notch and the screen's edge,
    /// where a line would show as a seam.
    var outerOnly = false
    /// Grown down past the notch and drawn in front of it: the outline also runs up its left side to the
    /// notch's bottom edge (this far down), meeting the notch's own outline there.
    var leftEdgeTo: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, s = Self.flare
        var path = Path()
        if outerOnly {
            path.move(to: CGPoint(x: w, y: 0))
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
        }
        path.addArc(tangent1End: CGPoint(x: w - s, y: 0), tangent2End: CGPoint(x: w - s, y: s), radius: s)
        path.addArc(tangent1End: CGPoint(x: w - s, y: h), tangent2End: CGPoint(x: 0, y: h), radius: 10)
        if h > 40 {
            // Grown down past the notch (over a tucked video): the bottom-left corner shows, so it's rounded too.
            path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: 10)
            if outerOnly, let top = leftEdgeTo { path.addLine(to: CGPoint(x: 0, y: top)) }
        } else {
            path.addLine(to: CGPoint(x: 0, y: h))
        }
        if !outerOnly { path.closeSubpath() }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// "Keep Info" in the open panel's top band, drawn like the tabs: on, the full dropdown stays open while it
/// holds something. (Large, which keeps just the video, comes from the video's ↓ tab instead.)
struct KeepButton: View {
    let mode: KeepMode
    let tint: Color
    let accent: Color
    let select: (KeepMode) -> Void

    var body: some View {
        Button { select(mode.next) } label: {
            HStack(spacing: 4) {
                Image(systemName: mode == .on ? "pin.fill" : "pin")
                Text("Keep Info")
            }
            .font(.caption.weight(.semibold))
            .frame(height: TabSegment.height)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .foregroundStyle(mode == .on ? accent : tint.opacity(0.6))
            .background(mode == .on ? accent.opacity(0.2) : .clear, in: Capsule())
            .contentShape(Capsule())
            .padding(2)
            .background(tint.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(mode == .on ? "Stop keeping it open" : "Keep the dropdown open")
    }
}

/// One segment the way `PanelTabs` draws its chosen one, in the same pill track, so lone buttons beside the
/// tabs (Video, Keep) have exactly the same size and margins.
struct TabSegment: ViewModifier {
    let on: Bool
    let tint: Color
    let accent: Color

    /// Every segment's content is this tall, icon-only or with a word, so all the top band's pills match.
    static let height: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .frame(height: Self.height)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(on ? accent : tint.opacity(0.6))
            .background(on ? accent.opacity(0.2) : .clear, in: Capsule())
            .contentShape(Capsule())
            .padding(2)
            .background(tint.opacity(0.08), in: Capsule())
    }
}

/// Today, Finder, Monitor: the chosen one shows its name, the others just their icon, so all three fit beside
/// the notch.
struct PanelTabs: View {
    /// nil while the content is folded away (a video is held).
    let selected: PanelTab?
    let tint: Color
    let accent: Color
    let select: (PanelTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                let on = tab == selected
                Button { select(tab) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: Self.icon(tab))
                        if on { Text(Self.title(tab)).transition(.opacity.combined(with: .move(edge: .leading))) }
                    }
                    .font(.caption.weight(.semibold))
                    .frame(height: TabSegment.height)
                    .padding(.horizontal, on ? 8 : 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(on ? accent : tint.opacity(0.6))
                    .background(on ? accent.opacity(0.2) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(Self.title(tab))
            }
        }
        .padding(2)
        .background(tint.opacity(0.08), in: Capsule())
        .animation(.spring(duration: 0.3, bounce: 0.2), value: selected)
    }

    static func title(_ tab: PanelTab) -> String {
        switch tab {
        case .today: "Today"
        case .finder: "Finder"
        case .monitor: "Monitor"
        case .browser: "Web"
        }
    }

    static func icon(_ tab: PanelTab) -> String {
        switch tab {
        case .today: "calendar"
        case .finder: "folder"
        case .monitor: "chart.xyaxis.line"
        case .browser: "globe"
        }
    }
}

/// Held apps' icons next to the time in the open dropdown, the same ones the tab shows while it's closed.
/// Click one to get its window back; drag it out and the dropdown closes and the app lifts into the pointer and
/// becomes its window, as from the tab.
struct HeldAppsRow: View {
    let state: AppState
    let dock: DockController
    /// Fixed columns (filling rows first, up to three rows of them); nil for the stacks of two beside the time.
    var columns: Int? = nil

    var body: some View {
        // Up to two side by side; past two they stack in twos (columns of two, three columns for six).
        let apps = state.dock.shownApps
        let rows = Array(repeating: GridItem(.fixed(Self.icon), spacing: Self.gap), count: apps.count > 2 ? 2 : 1)
        let grid = Array(repeating: GridItem(.fixed(Self.icon), spacing: Self.gap), count: columns ?? 1)
        Group {
            if let columns {
                // Fixed to its columns' width, so it takes exactly that room beside the time and never overlaps.
                LazyVGrid(columns: grid, alignment: .leading, spacing: Self.gap) { icons(apps) }
                    .frame(width: Self.gridWidth(columns: columns), alignment: .leading)
            } else {
                LazyHGrid(rows: rows, alignment: .top, spacing: 8) { icons(apps) }
            }
        }
        .fixedSize()
        .animation(.spring(duration: 0.4, bounce: 0.3), value: apps)
    }

    static let icon: CGFloat = 32
    static let gap: CGFloat = 6

    static func gridWidth(columns: Int) -> CGFloat {
        CGFloat(columns) * icon + CGFloat(columns - 1) * gap
    }

    @ViewBuilder
    private func icons(_ apps: [HeldApp]) -> some View {
            ForEach(apps) { app in
                let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSImage()
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Self.icon, height: Self.icon)
                    .overlay(alignment: .bottomTrailing) {
                        if let number = state.dock.number(of: app) { NumberBadge(number: number, accent: state.skin.accent, size: 14) }
                    }
                    .contentShape(Rectangle())
                    .help("\(app.appName): click to open it full desktop, Option-click to swap it with the window in front, drag it out to hold it, right-click to let go of it")
                    .onTapGesture { dock.restore(app) }
                    .contextMenu { Button("Let Go") { dock.letGo(app) } }
                    .gesture(DragGesture(minimumDistance: 3).onChanged { _ in dock.pullOut(app, icon: icon) })
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
    }
}

/// Holds the browser's Picture in Picture video in the notch, or gives it back. Shaped like the tabs' chosen
/// segment, with its icon where the closed notch's tab had it, so it reads as that button staying put while
/// the dropdown opens around it and "Video" slides out beside it.
struct VideoButton: View {
    let held: Bool
    let tint: Color
    let accent: Color
    let hold: () -> Void
    let giveBack: () -> Void
    /// Extra clickable room around it, up to the notch's corner and the top of the screen.
    var reach = EdgeInsets()
    @State private var named = false

    var body: some View {
        Button(action: held ? giveBack : hold) {
            HStack(spacing: 4) {
                Image(systemName: held ? "pip.exit" : "pip.enter")
                if named {
                    Text("Video").transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            // Grey like an unchosen tab until it holds a video, then in the skin's accent.
            .modifier(TabSegment(on: held, tint: tint, accent: accent))
            .padding(reach)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(held ? "Give the video back to the browser" : "Hold the Picture in Picture video here")
        .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.2).delay(0.25)) { named = true } }
        .onDisappear { named = false }
    }
}
