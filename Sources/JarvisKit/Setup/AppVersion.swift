/// A version like "1.3" or a release tag like "v1.10.2", compared number by number. As text, "1.10" would sort
/// before "1.9"; as numbers it's after. A missing number counts as 0, so 1.3 and 1.3.0 are the same version.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let numbers: [Int]

    /// nil for anything that isn't numbers between dots (after an optional "v").
    public init?(_ text: String) {
        var text = Substring(text.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text = text.dropFirst() }
        let numbers = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        self.numbers = numbers.compactMap { $0 }
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for (x, y) in a.padded(to: b) where x != y { return x < y }
        return false
    }

    /// Equal by number, so that it agrees with `<` (1.3 is neither before nor after 1.3.0).
    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        a.padded(to: b).allSatisfy { $0 == $1 }
    }

    public var description: String { numbers.map(String.init).joined(separator: ".") }

    /// Both versions' numbers side by side, the shorter one filled out with zeros.
    private func padded(to other: AppVersion) -> [(Int, Int)] {
        let count = max(numbers.count, other.numbers.count)
        let a = numbers + Array(repeating: 0, count: count - numbers.count)
        let b = other.numbers + Array(repeating: 0, count: count - other.numbers.count)
        return Array(zip(a, b))
    }
}
