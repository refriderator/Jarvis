import JarvisKit
import SwiftUI

/// Draws the notch for the current mode, hanging from the top of the panel.
/// Opening and closing play in two beats (see `NotchMotion`).
struct NotchView: View {
    let state: AppState
    let feed: WidgetFeed
    let assistant: Assistant
    let voice: VoiceSession
    let dock: DockController
    let monitor: MonitorFeed
    let browser: BrowserController
    let video: VideoController
    let openSettings: () -> Void
    let cancelTimer: (UUID) -> Void

    @State private var stage: NotchStage = .idle
    /// Bumped on every mode change, so a second beat that is no longer wanted is dropped.
    @State private var move = 0

    var body: some View {
        let skin = state.skin
        let size = size(stage)
        // Idle always matches the hardware notch: plain black, no shoulders.
        // Closed, the hardware notch has no shoulders; around a mini player it's skinned, shoulders included.
        let shoulder = skinned ? skin.shoulder : 0
        // The hole is only cut while the clamshell is off; with it on, the notch is solid and the clamshell (drawn
        // over the panel where the video really is, below) hides the video.
        let shape = NotchShape(radius: radius(stage, skin: skin), shoulder: shoulder,
                               hole: state.video.held && video.holeOpen
                                   ? videoHole(width: size.width + 2 * shoulder, lift: stage == .idle ? 0 : skin.lift) : nil)

        body(shape, skin: skin, glass: skin.material == .glass && skinned)
            .overlay(alignment: .top) {
                content
                    .padding(.horizontal, shoulder)
            }
            .frame(width: size.width + 2 * shoulder, height: size.height)
            .coordinateSpace(.named(NotchView.shapeSpace))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The side tab sits behind the notch, its left end tucked under it. A tucked video's tab, grown down
            // over the video, comes in front, so the notch's corner outline doesn't show through where they meet;
            // held apps' tab then comes in front of that one, along its top.
            .background { if !state.video.tucked { DockTab(state: state, dock: dock, video: video, stage: stage) } }
            .overlay {
                if state.video.tucked {
                    TuckedVideoTab(state: state, video: video, stage: stage)
                    DockTab(state: state, dock: dock, video: video, stage: stage)
                }
            }
            .overlay {
                // The video tucking away: the cover widening right, then shrinking into the side tab.
                if let morph = video.morph {
                    GeometryReader { geo in
                        TuckCover(morph: morph, skin: skin, tucked: state.video.tuckedSize, notchHeight: state.layout.notch.height,
                                  origin: CGPoint(x: geo.size.width / 2 - state.layout.notch.midX, y: state.layout.notch.maxY))
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay {
                // In the panel's own coordinates, over wherever the video window really is, so it's covered
                // even while the notch around it is moving (Liquid Glass is see-through).
                if state.video.held, !state.video.tucked, let frame = video.frameOnScreen {
                    GeometryReader { geo in
                        // This overlay is moved up with the open panel (its `lift`); the video isn't.
                        let lift = stage == .idle ? 0 : skin.lift
                        // 1 pt past the video on every side, so none of it shows while it moves; the edge (drawn
                        // from this inward) still hugs the hole.
                        let spot = CGRect(x: geo.size.width / 2 + frame.minX - state.layout.notch.midX,
                                          y: state.layout.notch.maxY - frame.maxY + lift,
                                          width: frame.width, height: frame.height)
                            .insetBy(dx: -VideoController.coverOutset, dy: -VideoController.coverOutset)
                        if video.showsControls {
                            VideoTabs(spot: spot, skin: skin, showsDown: video.showsDown, up: video.up, down: video.down)
                        }
                        VideoFrame(spot: spot, covered: state.video.covered, fill: clamshellFill(skin),
                                   // Only around the big video, once it's showing; there once the clamshell has gone.
                                   edge: stage == .open ? skin.accent.opacity(0.55) : nil)
                    }
                    .transition(.identity)
                }
            }
            .foregroundStyle(skin.foreground)
            .fontDesign(skin.fontDesign)
            // Some skins (Liquid Glass, Pink) show a faint light line along the very top of the screen; moving
            // the open panel up by the skin's `lift` hides it.
            .offset(y: stage == .idle ? 0 : -skin.lift)
            .animation(NotchMotion.peek, value: state.layout.showsCaption)
            .animation(NotchMotion.peek, value: state.layout.captionHeight)
            .animation(NotchMotion.peek, value: state.layout.showsShelf)
            .animation(NotchMotion.expand, value: state.layout.videoAspect)
            .animation(NotchMotion.expand, value: state.layout.hidesContent)
            .animation(NotchMotion.expand, value: state.layout.theater)
            .onChange(of: state.notch.mode) { old, new in animate(from: old, to: new) }
    }

    private func animate(from old: NotchMode, to new: NotchMode) {
        move += 1
        let current = move
        // Only opening and closing move a held video; a hover peek just widens the notch around it.
        guard state.video.held, (old == .open) != (new == .open) else { return play(from: old, to: new, current: current) }
        // A held video's static comes on first (and, closing, the video shrinks into its mini spot); then the
        // notch moves.
        Task {
            try? await Task.sleep(for: .seconds(VideoController.notchDelay(opening: new == .open)))
            guard move == current else { return }
            play(from: old, to: new, current: current)
        }
    }

    private func play(from old: NotchMode, to new: NotchMode, current: Int) {
        switch new {
        case .peek:
            withAnimation(NotchMotion.peek) { stage = .peek }
        case .open where old == .peek:
            // Already wider than the drop, so go straight to the widen.
            withAnimation(NotchMotion.expand) { stage = .open }
        case .open:
            withAnimation(NotchMotion.drop) { stage = .drop }
            Task {
                // Starts widening partway through the drop; SwiftUI blends the two from where it is.
                try? await Task.sleep(for: NotchMotion.expandDelay)
                guard move == current else { return }
                withAnimation(NotchMotion.expand) { stage = .open }
            }
        case .idle where stage == .open:
            withAnimation(NotchMotion.collapse) { stage = .drop } completion: {
                guard move == current else { return }
                withAnimation(NotchMotion.retract) { stage = .idle }
            }
        case .idle:
            // Every way back into the notch is smooth: the peek's spring would bounce on the way in
            // (a peek ending, or a close interrupted partway).
            withAnimation(NotchMotion.retract) { stage = .idle }
        }
    }

    @ViewBuilder
    private func body(_ shape: NotchShape, skin: Skin, glass: Bool) -> some View {
        if glass {
            Color.clear
                .glass(tint: skin.background.opacity(skin.glassDarkness), in: shape)
                .overlay {
                    NotchShape(radius: shape.radius, shoulder: shape.shoulder, openTop: true)
                        .stroke(skin.foreground.opacity(0.34), lineWidth: 0.8)
                }
        } else {
            shape
                // At rest it is the hardware notch: plain black whatever the skin, so no color shows around it.
                .fill(skinned ? skin.background.opacity(skin.backgroundOpacity) : Color.black)
                .shadow(color: skin.accent.opacity(skinned ? 0.7 : 0), radius: skin.glow)
                .mask { GlowMask(hole: shape.hole).padding(-GlowMask.reach) }
                .overlay {
                    // Always in the tree, fading in and out, so it is the same shape as the fill and
                    // grows and shrinks with it in every animation (adding and removing it would not).
                    if let border = skin.border {
                        NotchShape(radius: shape.radius, shoulder: shape.shoulder, openTop: true)
                            .stroke(border, lineWidth: skin.borderWidth)
                            .opacity(skinned ? 1 : 0)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle where state.layout.mediumVideoSize != nil, .peek where state.layout.mediumVideoSize != nil:
            // The Web tab's full-screen video as a medium player: just to watch (a click opens the dropdown).
            if let size = state.layout.mediumVideoSize, let page = browser.current {
                WebPageView(view: page.view)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: NotchLayout.videoHoleRadius))
                    .allowsHitTesting(false)
                    .padding(.top, state.layout.notch.height + 0.75 * NotchLayout.videoPad)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        case .idle where state.layout.isPill && (!state.video.held || state.video.tucked):
            // A display without a hardware notch: the pill shows the ticker instead of sitting there black (unless
            // it's showing a held video's mini player; a tucked video waits beside it).
            TickerView(state: state)
                .transition(.opacity)
        case .idle, .drop:
            EmptyView()
        case .peek:
            PeekView(accent: state.skin.accent, voice: state.voice, timer: state.timers.first)
                .frame(height: state.layout.notch.height)
                .transition(.opacity)
        case .open where state.layout.theater:
            // Keep Large: just the video, shown through the hole.
            Color.clear
                .transition(.opacity)
        case .open:
            OpenPanelView(state: state, feed: feed, assistant: assistant, voice: voice, openSettings: openSettings,
                          cancelTimer: cancelTimer, dock: dock, monitor: monitor, browser: browser, video: video)
                // Faded while the video moves to and from Large.
                .opacity(video.panelHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: video.panelHidden)
                .transition(NotchMotion.content)
        }
    }

    /// Where the video window really is, in the shape's own coordinates: the shape is `width` wide, centred
    /// on the notch, its top at the screen's top moved up by `lift`. Worked out from the shape actually drawn,
    /// so it can't drift from it (it did: the closed notch's shoulders were left out, 10 pt off).
    private func videoHole(width: CGFloat, lift: CGFloat) -> CGRect? {
        guard let frame = video.frameOnScreen else { return nil }
        let notch = state.layout.notch
        // From the shape's top centre: its width animates, its centre doesn't (measuring from the left edge with
        // the final width put the hole off the video while the notch widened on hover).
        return CGRect(x: frame.minX - notch.midX, y: notch.maxY + lift - frame.maxY,
                      width: frame.width, height: frame.height)
            .insetBy(dx: VideoController.holeInset, dy: VideoController.holeInset)
    }

    /// At rest the notch is the hardware notch, plain black; holding a video, the mini player around it is in
    /// the skin's colours like the open notch, so it stays the same colour through every step.
    private var skinned: Bool { stage != .idle || state.video.held || state.layout.mediumVideoSize != nil }

    /// The clamshell over a held video: black on the closed notch, the skin's colour open (grey on glass,
    /// which has no solid colour of its own).
    private func clamshellFill(_ skin: Skin) -> Color {
        if !skinned { return .black }
        return skin.material == .glass ? Color(white: 0.2) : skin.background.opacity(skin.backgroundOpacity)
    }

    /// The notch shape's own coordinates, for the video's spot.
    nonisolated static let shapeSpace = "notchShape"

    private func size(_ stage: NotchStage) -> CGSize {
        switch stage {
        case .idle: state.layout.size(for: .idle)
        case .peek: state.layout.size(for: .peek)
        case .drop: state.layout.dropSize
        case .open: state.layout.size(for: .open)
        }
    }

    /// Around a video (the mini player, and Large) the corners match each other and run concentric with the
    /// video's own.
    private func radius(_ stage: NotchStage, skin: Skin) -> CGFloat {
        let aroundVideo = state.layout.videoAspect != nil || state.layout.mediumVideoSize != nil
        switch stage {
        case .idle: return aroundVideo ? NotchLayout.videoCornerRadius : 8
        case .peek: return aroundVideo ? NotchLayout.videoCornerRadius : 13
        case .drop: return aroundVideo ? NotchLayout.videoCornerRadius : 12
        case .open: return state.layout.theater ? NotchLayout.videoCornerRadius : skin.cornerRadius
        }
    }
}

/// The frame a held video shows through: a thin edge around it, and a cover in two halves that closes over it
/// like a clamshell while the video moves, then parts to reveal it, with an old-TV flash on the seam.
private struct VideoFrame: View {
    let spot: CGRect
    /// The clamshell's colour.
    let fill: Color
    /// Only around the big video, once it's showing.
    let edge: Color?
    let covered: Bool

    init(spot: CGRect, covered: Bool, fill: Color, edge: Color?) {
        self.spot = spot
        self.covered = covered
        self.fill = fill
        self.edge = edge
    }

    var body: some View {
        // `spot` is the cover's (past the video's edges); the hole, and the edge around it, are inside it.
        let hole = spot.insetBy(dx: VideoController.holeInset + VideoController.coverOutset,
                                dy: VideoController.holeInset + VideoController.coverOutset)
        let radius = VideoController.cornerRadius
        ZStack(alignment: .topLeading) {
            if let edge {
                // Hugs the hole (the same rounded rectangle, 1.5 pt out), there once the picture is.
                RoundedRectangle(cornerRadius: radius + 1.5)
                    .strokeBorder(edge, lineWidth: 1.5)
                    .frame(width: hole.width + 3, height: hole.height + 3)
                    .offset(x: hole.minX - 1.5, y: hole.minY - 1.5)
                    .opacity(covered ? 0 : 1)
            }
            // The clamshell, clipped to the hole's rounded shape so its corners match, and as it opens an old-TV
            // flash along its seam.
            ZStack(alignment: .topLeading) {
                Rectangle().fill(fill)
                    .frame(width: spot.width, height: spot.height / 2)
                    .scaleEffect(x: 1, y: covered ? 1 : 0, anchor: .top)
                Rectangle().fill(fill)
                    .frame(width: spot.width, height: spot.height / 2)
                    .scaleEffect(x: 1, y: covered ? 1 : 0, anchor: .bottom)
                    .offset(y: spot.height / 2)
                CRTFlash(covered: covered, width: spot.width)
                    .frame(width: spot.width, height: spot.height)
            }
            .frame(width: spot.width, height: spot.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: radius + VideoController.holeInset + VideoController.coverOutset))
            .offset(x: spot.minX, y: spot.minY)
        }
        .animation(.easeInOut(duration: VideoController.cover), value: covered)
        .allowsHitTesting(false)
    }
}

/// The old-TV flash as the clamshell opens: a glowing dot that stretches into a bright line tapering to sharp
/// points, then goes out as the halves part. Closing is just the clamshell.
private struct CRTFlash: View {
    let covered: Bool
    let width: CGFloat
    @State private var stretch: CGFloat = 1
    @State private var glow: Double = 0

    var body: some View {
        ZStack {
            Streak()
                .fill(.white)
                .frame(width: width * stretch, height: 4)
                .shadow(color: .white, radius: 3)
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0.6), .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: 14))
                .frame(width: 28, height: 28)
                .scaleEffect(0.6 + 0.4 * glow)
        }
        .opacity(glow)
        .allowsHitTesting(false)
        .onChange(of: covered) { _, nowCovered in
            guard !nowCovered else { return }
            Task { @MainActor in
                var instant = Transaction(animation: nil)
                instant.disablesAnimations = true
                withTransaction(instant) { stretch = 0.02; glow = 1 }
                withAnimation(.easeOut(duration: 0.1)) { stretch = 1 }
                try? await Task.sleep(for: .seconds(0.08))
                withAnimation(.easeOut(duration: 0.16)) { glow = 0 }
            }
        }
    }
}

/// A lens: thickest in the middle, curving to sharp points at both ends.
private struct Streak: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height / 2))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height / 2))
        path.closeSubpath()
        return path
    }
}

/// The ↑ ↓ tabs over a held video while the pointer is on it, stacked in its middle (see
/// `VideoController.controlFrames`, which has the same sizes for letting clicks through everywhere else).
private struct VideoTabs: View {
    let spot: CGRect
    let skin: Skin
    let showsDown: Bool
    let up: () -> Void
    let down: () -> Void

    var body: some View {
        let size = VideoController.tabSize
        VStack(spacing: 4) {
            tab("chevron.up", action: up).help("Smaller")
            if showsDown { tab("chevron.down", action: down).help("Bigger") }
        }
        .frame(width: size.width, height: showsDown ? 2 * size.height + 4 : size.height)
        .position(x: spot.midX, y: spot.midY)
        .transition(.opacity)
    }

    private func tab(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Two chevrons, nested like a fast-forward sign turned on its side.
            VStack(spacing: -5) {
                Image(systemName: symbol)
                Image(systemName: symbol)
            }
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(skin.accent)
            .frame(width: VideoController.tabSize.width, height: VideoController.tabSize.height)
            .background(skin.background.opacity(0.9), in: Capsule())
            .overlay(Capsule().strokeBorder(skin.accent.opacity(0.5), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The one shape that moves while the video tucks away or comes back, drawn like the notch: the skin's fill
/// (glass on Liquid Glass), its border and glow, shoulders flaring into the menu bar; at rest the video icon
/// where the side tab shows it.
private struct TuckCover: View {
    let morph: TuckMorph
    let skin: Skin
    let tucked: CGSize?
    let notchHeight: CGFloat
    /// Screen point (0, 0) in this view's coordinates, flipped: x adds, y subtracts.
    let origin: CGPoint

    var body: some View {
        let f = morph.frame
        let shape = CoverShape(left: morph.leftShoulder, right: morph.rightShoulder, radius: morph.radius)
        ZStack(alignment: .topLeading) {
            if skin.material == .glass {
                Color.clear.glass(tint: skin.background.opacity(skin.glassDarkness), in: shape)
            } else {
                shape.fill(skin.background.opacity(skin.backgroundOpacity))
                    .shadow(color: skin.accent.opacity(0.7), radius: skin.glow)
            }
            if let border = skin.border {
                CoverShape(left: morph.leftShoulder, right: morph.rightShoulder, radius: morph.radius,
                           outline: true, leftEdgeTop: morph.leftEdgeTop)
                    .stroke(border, lineWidth: skin.borderWidth)
            }
            if morph.icon, tucked != nil {
                // Where the tab shows it: across the middle, in the part below the notch.
                TuckedVideoIcon(skin: skin)
                    .position(x: (f.width - morph.rightShoulder) / 2,
                              y: (notchHeight + f.height) / 2 - TuckedVideoIcon.lift)
                    .transition(.opacity)
            }
        }
        .frame(width: f.width, height: f.height)
        .position(x: origin.x + f.midX, y: origin.y - f.midY)
    }
}

/// The notch's outline with its own shoulder each side (0 for none), every number animatable so one shape can
/// become another. `outline` leaves the top out (and the left side above `leftEdgeTop`) for the border.
private struct CoverShape: Shape {
    var left: CGFloat
    var right: CGFloat
    var radius: CGFloat
    var outline = false
    var leftEdgeTop: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(left, right), AnimatablePair(radius, leftEdgeTop)) }
        set { (left, right, radius, leftEdgeTop) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let l = min(left, h / 2), rr = min(right, h / 2)
        let r = max(0, min(radius, (w - l - rr) / 2, h - max(l, rr)))
        var path = Path()
        if outline {
            path.move(to: CGPoint(x: l > 0.5 ? 0 : l, y: l > 0.5 ? 0 : min(leftEdgeTop, h - r)))
        } else {
            path.move(to: .zero)
        }
        if l > 0.5 { path.addArc(tangent1End: CGPoint(x: l, y: 0), tangent2End: CGPoint(x: l, y: l), radius: l) }
        path.addArc(tangent1End: CGPoint(x: l, y: h), tangent2End: CGPoint(x: w - rr, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: w - rr, y: h), tangent2End: CGPoint(x: w - rr, y: 0), radius: r)
        if rr > 0.5 { path.addArc(tangent1End: CGPoint(x: w - rr, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: rr) }
        path.addLine(to: CGPoint(x: w, y: 0))
        if !outline { path.closeSubpath() }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
