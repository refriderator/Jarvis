import SwiftUI

extension Skin {
    /// Black with a softened cyan arc-reactor glow.
    public static let arc = Skin(
        id: "arc", name: "Arc",
        background: .black, foreground: Color(red: 0.87, green: 0.94, blue: 0.96),
        accent: Color(red: 0.42, green: 0.77, blue: 0.89),
        cornerRadius: 26, glow: 14, fontDesign: .rounded)
}
