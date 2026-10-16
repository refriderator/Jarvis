import SwiftUI

extension Skin {
    /// Plain black, blends into the hardware notch.
    public static let midnight = Skin(
        id: "midnight", name: "Midnight",
        background: .black, foreground: .white, accent: Color(red: 0.55, green: 0.6, blue: 1),
        cornerRadius: 22, glow: 0, fontDesign: .default,
        surface: 0.1, surfaceEdge: Color(red: 0.55, green: 0.6, blue: 1).opacity(0.35))
}
