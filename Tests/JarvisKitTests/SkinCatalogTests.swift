import JarvisKit
import Testing

struct SkinCatalogTests {
    @Test func idsAreUnique() {
        let ids = SkinCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func lookupFallsBackForUnknownID() {
        #expect(SkinCatalog.skin(id: "arc").id == "arc")
        #expect(SkinCatalog.skin(id: "nope").id == SkinCatalog.fallback.id)
        #expect(SkinCatalog.fallback.id == "classic")
    }

    @Test func pinkIsRegistered() {
        #expect(SkinCatalog.skin(id: "pink").name == "Pink")
    }

    @MainActor @Test func appStateSwitchesSkin() {
        let state = AppState()
        state.selectSkin(id: "terminal")
        #expect(state.skin.id == "terminal")
    }
}
