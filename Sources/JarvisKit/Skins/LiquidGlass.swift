import SwiftUI

extension Skin {
    /// See-through Liquid Glass with a flat top and a thin light edge.
    public static let liquidGlass = Skin(
        id: "glass", name: "Liquid Glass",
        background: .black, foreground: .white, accent: Color(white: 0.9),
        cornerRadius: 26, glow: 0, fontDesign: .default, material: .glass,
        glassDarkness: 0.22, lift: 1)
}
