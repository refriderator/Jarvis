import Foundation
import JarvisKit
import Testing

struct MacAdviceTests {
    private func mac(_ chip: String = "Apple M3", memory: Int, disk: Int = 200, id: String = "Mac15,3",
                     notch: Bool = true, appleIntelligence: Bool = true) -> MacProfile {
        MacProfile(modelID: id, chip: chip, memoryGB: memory, freeDiskGB: disk,
                   hasNotch: notch, appleIntelligence: appleIntelligence)
    }

    @Test func bigMacsGetTheEightB() {
        let advice = MacAdvice.for(mac(memory: 24))
        #expect(advice.fit == .great)
        #expect(advice.localBrain == .builtIn)
        #expect(advice.model?.id == "qwen3-8b")
        #expect(advice.warnings.contains { $0.contains("battery") })
    }

    @Test func sixteenGigsGetTheFourB() {
        #expect(MacAdvice.for(mac(memory: 16)).model?.id == "qwen3-4b")
    }

    @Test func eightGigsStayOnAppleIntelligence() {
        let advice = MacAdvice.for(mac(memory: 8, appleIntelligence: false))
        #expect(advice.fit == .light)
        #expect(advice.localBrain == .apple)
        #expect(advice.model == nil)
        #expect(advice.warnings.contains { $0.contains("Apple Intelligence is off") })
    }

    @Test func lowDiskFallsBack() {
        let advice = MacAdvice.for(mac(memory: 32, disk: 6))
        #expect(advice.localBrain == .apple)
        #expect(advice.warnings.contains { $0.contains("disk") })
    }

    @Test func intelIsCloudOnly() {
        let advice = MacAdvice.for(mac("Intel(R) Core(TM) i7", memory: 16, id: "MacBookPro16,1", notch: false))
        #expect(advice.fit == .cloudOnly)
        #expect(advice.localBrain == .off)
        #expect(advice.warnings.contains { $0.contains("notch") })
    }

    @Test func knownNotchMacsHaveNames() {
        #expect(mac(memory: 16).name == "MacBook Pro 14\" (M3, 2023)")
        #expect(mac("Apple M9", memory: 16, id: "Mac99,1").name == "Mac with Apple M9")
    }
}

struct ClaudeCodeSetupTests {
    @Test func readsAuthStatus() {
        let yes = Data(#"{"loggedIn": true, "authMethod": "claude.ai", "email": "a@b.c"}"#.utf8)
        #expect(ClaudeCodeSetup.parseStatus(yes) == .ready(account: "a@b.c"))
        #expect(ClaudeCodeSetup.parseStatus(Data(#"{"loggedIn": false}"#.utf8)) == .signedOut)
        #expect(ClaudeCodeSetup.parseStatus(Data("nope".utf8)) == .signedOut)
    }
}
