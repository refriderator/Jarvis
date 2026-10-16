import SwiftUI

extension Skin {
    /// Cute muted rose pink with a dark pink border, plum text and a soft glow.
    public static let pink = Skin(
        id: "pink", name: "Pink",
        background: Color(red: 0.88, green: 0.64, blue: 0.75), foreground: Color(red: 0.27, green: 0.07, blue: 0.2),
        accent: Color(red: 0.8, green: 0.33, blue: 0.55),
        cornerRadius: 30, glow: 8, fontDesign: .rounded, shoulder: 10,
        border: Color(red: 0.62, green: 0.2, blue: 0.4), lift: 1)
}
