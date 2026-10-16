import SwiftUI

/// What the notch body is made of.
public enum SkinMaterial: Sendable {
    /// Filled with `background`.
    case solid
    /// Apple's Liquid Glass, darkened with `background` so white text stays readable.
    case glass
}

/// The whole look of Jarvis in one value. Add a skin: new file with a
/// `static let` on `Skin`, then list it in `SkinCatalog.all`.
public struct Skin: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let background: Color
    public let foreground: Color
    public let accent: Color
    /// Bottom corners of the open panel.
    public let cornerRadius: CGFloat
    /// Accent glow radius around the panel; 0 for none.
    public let glow: CGFloat
    public let fontDesign: Font.Design
    /// Concave curves at the top corners that blend the panel into the menu bar; 0 for a straight drop.
    public let shoulder: CGFloat
    public let material: SkinMaterial
    /// How much `background` darkens Liquid Glass (0 clear, 1 solid); lower is lighter.
    public let glassDarkness: Double
    /// How opaque a solid `background` is (1 solid; lower lets the screen behind show through).
    public let backgroundOpacity: Double
    /// A line around the sides and bottom (not the top edge), or nil for none.
    public let border: Color?
    public let borderWidth: CGFloat
    /// Points the open panel is moved up, to hide a light line along the very top of the screen.
    public let lift: CGFloat
    /// How strongly boxes inside the open panel (the Finder tab) are tinted with `foreground`; higher stands
    /// out more against a black panel.
    public let surface: Double
    /// A line around those boxes, or nil for none.
    public let surfaceEdge: Color?

    public init(id: String, name: String, background: Color, foreground: Color, accent: Color,
                cornerRadius: CGFloat, glow: CGFloat, fontDesign: Font.Design,
                shoulder: CGFloat = 0, material: SkinMaterial = .solid, glassDarkness: Double = 0.34,
                backgroundOpacity: Double = 1, border: Color? = nil, borderWidth: CGFloat = 1.5, lift: CGFloat = 0,
                surface: Double = 0.05, surfaceEdge: Color? = nil) {
        self.id = id
        self.name = name
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.glow = glow
        self.fontDesign = fontDesign
        self.shoulder = shoulder
        self.material = material
        self.glassDarkness = glassDarkness
        self.backgroundOpacity = backgroundOpacity
        self.border = border
        self.borderWidth = borderWidth
        self.lift = lift
        self.surface = surface
        self.surfaceEdge = surfaceEdge
    }
}
