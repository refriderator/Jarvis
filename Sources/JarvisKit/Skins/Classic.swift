import SwiftUI

extension Skin {
    /// The original Jarvis look: black and greys, with shoulders flowing into the menu bar.
    public static let classic = Skin(
        id: "classic", name: "Classic",
        background: .black, foreground: .white, accent: Color(white: 0.75),
        cornerRadius: 26, glow: 0, fontDesign: .rounded, shoulder: 10,
        surface: 0.11, surfaceEdge: Color(white: 0.75).opacity(0.25))
}
