import JarvisKit
import Testing

struct AssistantNameTests {
    @Test func emptyMeansJarvis() {
        #expect(AssistantName.display("  ") == "Jarvis")
        #expect(AssistantName.display(" Nova ") == "Nova")
    }

    @Test func plainNamesAreFine() {
        #expect(AssistantName.warnings(for: "Jarvis").isEmpty)
        #expect(AssistantName.warnings(for: "Nova").isEmpty)
        #expect(AssistantName.warnings(for: "Mary-Jane").isEmpty)
    }

    @Test func warnsAboutNamesThatGetInTheWay() {
        #expect(AssistantName.warnings(for: "Claude").count == 1)
        #expect(AssistantName.warnings(for: "Alexa").count == 1)
        #expect(AssistantName.warnings(for: "Timer").count == 1)
        #expect(AssistantName.warnings(for: "Al").count == 1)
        #expect(AssistantName.warnings(for: "R2D2").count == 1)
    }

    @Test func dropsTheNameAtTheStart() {
        #expect(AssistantName.dropAddress("Hey Nova, set a timer for 5 minutes", name: "Nova") == "set a timer for 5 minutes")
        #expect(AssistantName.dropAddress("jarvis what's on tomorrow", name: "") == "what's on tomorrow")
        #expect(AssistantName.dropAddress("Is Nova a star?", name: "Nova") == "Is Nova a star?", "only at the start")
        #expect(AssistantName.dropAddress("Novak Djokovic's age", name: "Nova") == "Novak Djokovic's age", "whole word only")
        #expect(AssistantName.dropAddress("Nova", name: "Nova") == "Nova", "just the name stays a question")
    }

    @Test func cloudPersonaUsesTheName() {
        #expect(Persona.cloud(name: "Nova").hasPrefix("You are Nova,"))
        #expect(!Persona.localTools.contains("Jarvis"), "the trained local prompt never names it")
    }
}
