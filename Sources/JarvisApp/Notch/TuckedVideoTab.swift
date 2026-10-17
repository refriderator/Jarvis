import JarvisKit
import SwiftUI

/// The tab over a tucked video, beside the notch and down over the video, wearing the video icon. Click it to
/// bring the mini player back. Held apps' tab sits in front of it along the top: this one has that tab's shape cut
/// out, sliding with it, so on Liquid Glass the two never overlap as a darker band (and solid skins never show
/// this tab's border under it).
struct TuckedVideoTab: View {
    let state: AppState
    let video: VideoController
    let stage: NotchStage

    var body: some View {
        GeometryReader { geo in
            let layout = state.layout
            if let frame = layout.videoTabFrame {
                let shown = stage == .idle && video.morph == nil
                // It appears in place at the end of the tuck (the cover was its shape), so no bounce.
                TabBody(skin: state.skin, shown: shown, width: frame.width + DockTabShape.flare, bounce: false,
                        notchHeight: layout.notch.height, height: frame.height) { EmptyView() }
                    // It bounces out when the pointer arrives and stays out while it's there, then eases back in
                    // (no bounce) when it leaves: stretched from its top edge, so the video stays covered all the while.
                    .scaleEffect(x: 1, y: 1 + drop / max(frame.height, 1), anchor: .top)
                    .mask(alignment: .topLeading) { cutOut(layout) }
                    .overlay(alignment: .topLeading) {
                        // Centred across the tab and in the part below the notch. It rides the bounce where the
                        // stretch takes its spot, unstretched.
                        if shown {
                            let y = (layout.notch.height + frame.height) / 2 - TuckedVideoIcon.lift
                            TuckedVideoIcon(skin: state.skin)
                                .position(x: frame.width / 2, y: y)
                                .offset(y: drop * y / max(frame.height, 1))
                                .help("Bring the video back")
                                .transition(.opacity)
                        }
                    }
                    .animation(video.pointerOverTab ? .spring(duration: 0.4, bounce: 0.5) : .easeOut(duration: 0.2),
                               value: video.pointerOverTab)
                    .besideNotch(frame, layout: layout, out: shown, in: geo)
                    .onTapGesture { video.untuck() }
            }
        }
    }

    /// Everything (glow included) but held apps' tab, where and while it's out, moving as it does.
    private func cutOut(_ layout: NotchLayout) -> some View {
        let apps = layout.tabFrame
        let width = apps.width + DockTabShape.flare
        let appsOut = stage == .idle && layout.showsTab && video.morph == nil
        return ZStack(alignment: .topLeading) {
            Rectangle().padding(-GlowMask.reach)
            if layout.showsTab {
                DockTabShape()
                    .frame(width: width, height: apps.height)
                    .offset(x: appsOut ? 0 : -width)
                    .animation(TabBody<EmptyView>.motion(shown: appsOut), value: appsOut)
                    .blendMode(.destinationOut)
            }
        }
        .animation(DockTab.resize, value: layout.tabSlots)
        .compositingGroup()
    }

    /// How far the tab's bottom is out: dropped while the pointer is on it.
    private var drop: CGFloat { video.pointerOverTab ? 13 : 0 }
}
