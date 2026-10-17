import JarvisKit
import SwiftUI

/// The video icon on the side tab over a tucked video (and on the cover while it tucks, so the two match).
/// On Liquid Glass the video shows through the tab, so the icon sits on a dark capsule, shaped like the tabs'
/// track, that dims the video behind it without blacking it out.
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
                    Capsule()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 40, height: 24)
                }
            }
    }
}
