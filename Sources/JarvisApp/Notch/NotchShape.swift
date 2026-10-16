import SwiftUI

/// The notch body: flat top against the screen edge, rounded bottom corners, and
/// optional concave shoulders that flare the top corners into the menu bar.
/// `rect` includes the shoulders, so the body is `shoulder` narrower on each side.
struct NotchShape: Shape {
    var radius: CGFloat
    var shoulder: CGFloat
    /// Leave out the top edge, for stroking just the sides and bottom.
    var openTop = false
    /// A held video shows through here (in the shape's own coordinates), from the window below.
    var hole: CGRect?

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(radius, shoulder) }
        set { (radius, shoulder) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let s = min(shoulder, h / 2)
        let r = max(0, min(radius, (w - 2 * s) / 2, h - s))
        var path = Path()
        // Clockwise from the top-left corner (y grows downward).
        path.move(to: CGPoint(x: 0, y: 0))
        path.addArc(tangent1End: CGPoint(x: s, y: 0), tangent2End: CGPoint(x: s, y: s), radius: s)
        path.addArc(tangent1End: CGPoint(x: s, y: h), tangent2End: CGPoint(x: w - s, y: h), radius: r)
        path.addArc(tangent1End: CGPoint(x: w - s, y: h), tangent2End: CGPoint(x: w - s, y: 0), radius: r)
        path.addArc(tangent1End: CGPoint(x: w - s, y: 0), tangent2End: CGPoint(x: w, y: 0), radius: s)
        path.addLine(to: CGPoint(x: w, y: 0))
        if !openTop {
            path.closeSubpath()
        }
        if let hole {
            // `hole` is measured from the top centre, which stays put while the shape's width animates.
            path = path.subtracting(Path(roundedRect: hole.offsetBy(dx: w / 2, dy: 0), cornerRadius: VideoController.cornerRadius))
        }
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Everything around the notch but its hole, so the skin's glow (a shadow, which also falls inward) stays off
/// the video's edges; it washed them in the accent colour.
struct GlowMask: Shape {
    var hole: CGRect?

    /// How far past the shape the mask reaches, so the glow outside it isn't cut off. The mask view is given
    /// this much padding on every side (a mask only covers its own frame).
    static let reach: CGFloat = 60

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole {
            path = path.subtracting(Path(roundedRect: hole.offsetBy(dx: rect.midX, dy: rect.minY + Self.reach),
                                         cornerRadius: VideoController.cornerRadius))
        }
        return path
    }
}
