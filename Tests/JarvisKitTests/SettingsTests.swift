import Foundation
import JarvisKit
import Testing

struct SettingsTests {
    @Test func missingFieldsKeepTheirDefaults() throws {
        let saved = Data(#"{"skinID": "arc"}"#.utf8)
        let settings = try Settings.decode(saved)
        #expect(settings.skinID == "arc")
        #expect(settings.openTrigger == Settings().openTrigger)
        #expect(settings.speechRate == Settings().speechRate)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let saved = Data(#"{"someRemovedSetting": 3, "talkMode": "toggle"}"#.utf8)
        #expect(try Settings.decode(saved).talkMode == .toggle)
    }

    @Test func fileStoreRoundTripsAndToleratesGarbage() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "jarvis-\(UUID())/settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileSettingsStore(url: url)
        #expect(store.load() == Settings())

        var settings = Settings()
        settings.voiceID = "com.apple.voice.premium.en-US.Zoe"
        settings.captionSize = .large
        store.save(settings)
        #expect(store.load() == settings)

        try Data("not json".utf8).write(to: url)
        #expect(store.load() == Settings())
    }

    @Test func settingsFileNeverContainsSecrets() throws {
        let json = String(decoding: try JSONEncoder().encode(Settings()), as: UTF8.self).lowercased()
        #expect(!json.contains("apikey"))
        #expect(!json.contains("token\""))
    }
}
