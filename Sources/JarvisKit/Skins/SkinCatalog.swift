/// The one list of skins. The menu's Skin submenu and the Appearance tab both read it.
public enum SkinCatalog {
    public static let all: [Skin] = [.classic, .liquidGlass, .midnight, .arc, .pink, .terminal]

    public static var fallback: Skin { all[0] }

    public static func skin(id: String) -> Skin {
        all.first { $0.id == id } ?? fallback
    }
}
