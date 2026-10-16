import JarvisKit
import SwiftUI

/// The video icon on the side tab over a tucked video (and on the cover while it tucks, so the two match).
/// On Liquid Glass the video shows through the tab, so the icon sits on a dark oval that hides most of it; the
/// oval's soft edge lets a little of the video's glow show round it as a rim.
struct TuckedVideoIcon: View {
    let skin: Skin

    /// A little above the middle of the part below the notch.
    static let lift: CGFloat = 3

    var body: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(skin.accent)
            .background {
                if skin.material == .glass {
                    Ellipse()
                        .fill(Color.black.opacity(0.78))
                        .frame(width: 42, height: 28)
                        .blur(radius: 2)
                }
            }
    }
}
