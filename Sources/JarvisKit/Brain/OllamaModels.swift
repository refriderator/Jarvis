import Foundation

/// The models pulled into Ollama on this Mac, for the Settings picker.
public enum OllamaModels {
    public static let tagsURL = URL(string: "http://localhost:11434/api/tags")!

    /// Installed model names, sorted; empty if Ollama isn't running.
    public static func installed() async -> [String] {
        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return (try? parse(data)) ?? []
    }

    public static func parse(_ data: Data) throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable { let name: String }
            let models: [Model]
        }
        return try JSONDecoder().decode(Response.self, from: data).models.map(\.name).sorted()
    }
}
