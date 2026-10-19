import JarvisKit
import Testing

struct AppVersionTests {
    private func version(_ text: String) -> AppVersion { AppVersion(text)! }

    /// The trap: as text, "1.10" < "1.9".
    @Test func tenIsAfterNine() {
        #expect(version("1.9") < version("1.10"))
    }

    @Test func missingNumbersAreZero() {
        #expect(version("1.3") == version("1.3.0"))
        #expect(!(version("1.3") < version("1.3.0")))
        #expect(version("1.3") < version("1.3.1"))
    }

    @Test func readsReleaseTags() {
        #expect(version("v2.0") == version("2"))
        #expect(version("v1.3").description == "1.3")
    }

    @Test func rejectsWhatIsNotAVersion() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.3-beta") == nil)
        #expect(AppVersion("1..3") == nil)
        #expect(AppVersion("latest") == nil)
    }
}
