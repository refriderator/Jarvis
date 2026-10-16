import Foundation

/// What this Mac is and what it can handle, for picking a local brain.
public struct MacProfile: Equatable, Sendable {
    /// `hw.model`, e.g. "Mac15,3".
    public var modelID: String
    /// e.g. "Apple M3 Pro"; Intel Macs report an Intel brand string.
    public var chip: String
    public var memoryGB: Int
    public var freeDiskGB: Int
    public var hasNotch: Bool
    public var appleIntelligence: Bool

    public init(modelID: String, chip: String, memoryGB: Int, freeDiskGB: Int,
                hasNotch: Bool, appleIntelligence: Bool) {
        self.modelID = modelID
        self.chip = chip
        self.memoryGB = memoryGB
        self.freeDiskGB = freeDiskGB
        self.hasNotch = hasNotch
        self.appleIntelligence = appleIntelligence
    }

    public var isAppleSilicon: Bool { chip.hasPrefix("Apple") }
    public var name: String { NotchMacs.name(modelID) ?? "Mac with \(chip)" }
    public var isLaptop: Bool { name.contains("MacBook") }

    @MainActor
    public static func current(hasNotch: Bool) -> MacProfile {
        let free = (try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? nil
        return MacProfile(modelID: sysctl("hw.model") ?? "Mac",
                          chip: sysctl("machdep.cpu.brand_string") ?? "Apple silicon",
                          memoryGB: Int(ProcessInfo.processInfo.physicalMemory >> 30),
                          freeDiskGB: Int((free ?? 0) >> 30),
                          hasNotch: hasNotch,
                          appleIntelligence: AppleOnDeviceProvider.isAvailable)
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// Macs that have a notch, by model identifier. Only used for a friendly name;
/// the advice itself comes from the chip and memory, so newer Macs work without an entry.
public enum NotchMacs {
    public static let names: [String: String] = [
        "MacBookPro18,1": "MacBook Pro 16\" (M1 Pro, 2021)", "MacBookPro18,2": "MacBook Pro 16\" (M1 Max, 2021)",
        "MacBookPro18,3": "MacBook Pro 14\" (M1 Pro, 2021)", "MacBookPro18,4": "MacBook Pro 14\" (M1 Max, 2021)",
        "Mac14,2": "MacBook Air 13\" (M2, 2022)", "Mac14,15": "MacBook Air 15\" (M2, 2023)",
        "Mac14,9": "MacBook Pro 14\" (M2 Pro, 2023)", "Mac14,5": "MacBook Pro 14\" (M2 Max, 2023)",
        "Mac14,10": "MacBook Pro 16\" (M2 Pro, 2023)", "Mac14,6": "MacBook Pro 16\" (M2 Max, 2023)",
        "Mac15,3": "MacBook Pro 14\" (M3, 2023)",
        "Mac15,6": "MacBook Pro 14\" (M3 Pro, 2023)", "Mac15,8": "MacBook Pro 14\" (M3 Max, 2023)",
        "Mac15,10": "MacBook Pro 14\" (M3 Max, 2023)", "Mac15,7": "MacBook Pro 16\" (M3 Pro, 2023)",
        "Mac15,9": "MacBook Pro 16\" (M3 Max, 2023)", "Mac15,11": "MacBook Pro 16\" (M3 Max, 2023)",
        "Mac15,12": "MacBook Air 13\" (M3, 2024)", "Mac15,13": "MacBook Air 15\" (M3, 2024)",
        "Mac16,1": "MacBook Pro 14\" (M4, 2024)", "Mac16,6": "MacBook Pro 14\" (M4 Max, 2024)",
        "Mac16,8": "MacBook Pro 14\" (M4 Pro, 2024)", "Mac16,5": "MacBook Pro 16\" (M4 Max, 2024)",
        "Mac16,7": "MacBook Pro 16\" (M4 Pro, 2024)",
        "Mac16,12": "MacBook Air 13\" (M4, 2025)", "Mac16,13": "MacBook Air 15\" (M4, 2025)",
    ]

    public static func name(_ modelID: String) -> String? { names[modelID] }
}
