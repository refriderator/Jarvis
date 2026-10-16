import SwiftUI

extension Skin {
    /// Green-on-black, monospaced, square-ish.
    public static let terminal = Skin(
        id: "terminal", name: "Terminal",
        background: .black, foreground: Color(red: 0.6, green: 1, blue: 0.6),
        accent: Color(red: 0.2, green: 0.9, blue: 0.3),
        cornerRadius: 10, glow: 6, fontDesign: .monospaced,
        surface: 0.1, surfaceEdge: Color(red: 0.2, green: 0.9, blue: 0.3).opacity(0.35))
}
