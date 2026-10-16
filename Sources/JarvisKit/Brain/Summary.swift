import Foundation

/// An answer turned into something quick to read: a few short points with an icon each, and, when the
/// answer has them, its key formula and a small bar chart. The cloud brain writes it as JSON (see `prompt`).
public struct Summary: Equatable, Sendable, Codable {
    public struct Point: Equatable, Sendable, Codable {
        /// An SF Symbols name; the caption falls back to a dot when it isn't a real one.
        public var symbol: String?
        public var text: String

        public init(symbol: String?, text: String) {
            self.symbol = symbol
            self.text = text
        }
    }

    public struct Bar: Equatable, Sendable, Codable {
        public var label: String
        public var value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public var points: [Point]
    /// The equation or number the answer hangs on, in plain maths (x², √2, π); nil when there isn't one.
    public var formula: String?
    /// 2 to 6 quantities in one unit to compare; empty when the answer doesn't compare any.
    public var bars: [Bar]
    public var unit: String?

    public init(points: [Point], formula: String? = nil, bars: [Bar] = [], unit: String? = nil) {
        self.points = points
        self.formula = formula
        self.bars = bars
        self.unit = unit
    }

    public static let maxPoints = 5
    public static let maxBars = 6

    public static let prompt = """
        Turn the answer below into a summary that can be read at a glance in a small panel. Reply with only one \
        JSON object and nothing else, shaped like this:
        {"points": [{"symbol": "bolt.fill", "text": "Charge flows from high to low potential"}], \
        "formula": "V = IR", "bars": [{"label": "Copper", "value": 1.7}], "unit": "×10⁻⁸ Ω·m"}
        points: 2 to 5, each one short line under 12 words, plain text. symbol: a real SF Symbols name that fits \
        the point (like clock, bolt.fill, function, ruler, exclamationmark.triangle, checkmark.circle). \
        formula: only if the answer centres on one equation or one key number, else "". \
        bars and unit: only if the answer compares 2 to 6 numbers in the same unit, else [] and "". \
        Never use LaTeX or markdown; write maths with plain symbols (x², √2, 3/4, π, ≤).
        """

    /// The JSON in a model's reply, tidied for the caption; nil when there's none or it has no points.
    public static func parse(_ reply: String) -> Summary? {
        // Models wrap JSON in prose or ``` fences now and then: take the outermost braces.
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(reply[start...end].utf8)) else { return nil }
        let points = (raw.points ?? [])
            .map { Point(symbol: $0.symbol?.trimmingCharacters(in: .whitespaces), text: Readable.clean($0.text)) }
            .filter { !$0.text.isEmpty }
            .prefix(maxPoints)
        guard !points.isEmpty else { return nil }
        let bars = raw.bars ?? []
        return Summary(points: Array(points),
                       formula: raw.formula.map(Readable.clean).flatMap { $0.isEmpty ? nil : $0 },
                       // One bar compares nothing; too many won't fit.
                       bars: (2...maxBars).contains(bars.count) ? bars : [],
                       unit: raw.unit.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// What the model sends, where anything may be missing.
    private struct Raw: Decodable {
        var points: [Point]?
        var formula: String?
        var bars: [Bar]?
        var unit: String?
    }
}
