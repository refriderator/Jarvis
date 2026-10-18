import Foundation

/// A model Jarvis can download and run itself (GGUF, via llama.cpp).
public struct LocalModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let fileName: String
    /// Where to download it; nil for a custom model copied into `LocalModels.folder` by hand.
    public let url: URL?
    /// Exact size of a download (checks it arrived whole); about the size, for a trained model.
    public let bytes: Int64
    /// Rough memory the Mac needs to run it comfortably.
    public let minMemoryGB: Int

    public var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

public enum LocalModels {
    private static func qwen3(_ size: String, file: String, bytes: Int64, minMemoryGB: Int) -> LocalModel {
        LocalModel(id: "qwen3-\(size)", name: "Qwen3 \(size.uppercased())", fileName: file,
                   url: URL(string: "https://huggingface.co/Qwen/Qwen3-\(size.uppercased())-GGUF/resolve/main/\(file)")!,
                   bytes: bytes, minMemoryGB: minMemoryGB)
    }

    /// Smallest first.
    public static let all: [LocalModel] = [
        qwen3("1.7b", file: "Qwen3-1.7B-Q8_0.gguf", bytes: 1_834_426_016, minMemoryGB: 8),
        qwen3("4b", file: "Qwen3-4B-Q4_K_M.gguf", bytes: 2_497_280_256, minMemoryGB: 16),
        qwen3("8b", file: "Qwen3-8B-Q4_K_M.gguf", bytes: 5_027_783_488, minMemoryGB: 24),
        // Above the 8B's 24 GB so it's never picked for a Mac by default; 24 GB Macs can still choose it.
        qwen3("14b", file: "Qwen3-14B-Q4_K_M.gguf", bytes: 9_001_752_960, minMemoryGB: 32),
        // Qwen3 8B fine-tuned on Jarvis's own tools. Not downloadable: listed in Settings only once its file is in
        // `folder` (its fine-tuning lives outside this repo), and never recommended.
        // Qwen3 4B fine-tuned on the smaller job (timers, apps, Quick Dock, maths, handing on): v15b scored 340/340 on
        // both eval seeds with none confidently wrong (10-17), in half the memory. Downloadable from Hugging Face, and
        // the recommended (default) model on any Mac with enough memory for it.
        LocalModel(id: "jarvis-4b", name: "Jarvis 4B (trained)", fileName: "Jarvis-4B-Q4_K_M.gguf",
                   url: URL(string: "https://huggingface.co/refriderator/jarvis-qwen3-4b/resolve/main/Jarvis-4B-Q4_K_M.gguf")!,
                   bytes: 2_497_280_672, minMemoryGB: 16),
        LocalModel(id: "jarvis-8b", name: "Jarvis 8B (trained)", fileName: "Jarvis-8B-Q4_K_M.gguf", url: nil,
                   bytes: 5_027_783_904, minMemoryGB: 24),
    ]

    public static func model(id: String) -> LocalModel? { all.first { $0.id == id } }

    /// What Settings offers: everything downloadable, plus a custom model once it's installed.
    public static var offered: [LocalModel] { all.filter { $0.url != nil || isInstalled($0) } }

    /// Jarvis 4B (trained) when it fits this Mac's memory, else the biggest stock model that does.
    public static func recommended(memoryGB: Int = Int(ProcessInfo.processInfo.physicalMemory >> 30)) -> LocalModel {
        if let trained = model(id: "jarvis-4b"), trained.minMemoryGB <= memoryGB { return trained }
        return all.last { $0.url != nil && !$0.id.hasPrefix("jarvis-") && $0.minMemoryGB <= memoryGB } ?? all[0]
    }

    public static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Jarvis/Models", directoryHint: .isDirectory)
    }

    public static func fileURL(_ model: LocalModel) -> URL { folder.appending(path: model.fileName) }

    public static func isInstalled(_ model: LocalModel) -> Bool {
        guard let size = (try? fileURL(model).resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap({ $0 }) else { return false }
        // A hand-copied trained model's size changes with each export; any file there is it.
        return model.url == nil ? size > 0 : Int64(size) == model.bytes
    }
}
