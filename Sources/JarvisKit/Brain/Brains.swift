import Foundation

/// Builds the local and cloud brains from current settings and stored secrets.
@MainActor
public enum Brains {
    public static let ollamaURL = "http://localhost:11434/v1"

    public static func local(_ settings: Settings, engine: LlamaEngine) -> ChatProvider? {
        switch settings.localBrain {
        case .apple: AppleOnDeviceProvider.isAvailable ? AppleOnDeviceProvider() : nil
        case .builtIn:
            LocalModels.model(id: settings.builtInModelID).flatMap {
                LocalModels.isInstalled($0) ? LlamaProvider(engine: engine, model: $0) : nil
            }
        case .ollama: OpenAICompatibleProvider(baseURL: ollamaURL, model: settings.ollamaModel, apiKey: nil, label: "Ollama",
                                                skipThinking: true)
        case .off: nil
        }
    }

    public static func cloud(_ settings: Settings, secret: (SecretKey) -> String?) -> ChatProvider? {
        switch settings.cloudBrain {
        case .claudeCode:
            return ClaudeCodeProvider.find().map { ClaudeCodeProvider(executable: $0, model: settings.claudeModel) }
        case .codex:
            return CodexProvider.find().map { CodexProvider(executable: $0, model: settings.codexModel) }
        case .claude:
            return secret(.claudeAPIKey).map { ClaudeAPIProvider(apiKey: $0, model: settings.claudeModel) }
        case .openAICompatible:
            return OpenAICompatibleProvider(baseURL: settings.compatibleBaseURL, model: settings.compatibleModel,
                                            apiKey: secret(.compatibleAPIKey), label: settings.compatibleModel)
        }
    }
}
