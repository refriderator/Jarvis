import Foundation

/// A calculator for the local brain. Small models get arithmetic wrong ("38 minutes = 1368 seconds"),
/// so they write the sum and this works it out exactly. Needs no setup, so it is always offered.
/// Fine-tuning data is checked against a port of `evaluate` and `format`; change them together.
public struct MathTools: ToolKit {
    public let name = "math"

    public init() {}

    public var instructions: String { "Work out arithmetic exactly." }

    public var definitions: [ToolDefinition] {
        [
            ToolDefinition(name: "calculate", description: "Work out arithmetic exactly: + - * / ^, brackets and % (15% means 0.15). Use it for every sum, percentage or unit conversion instead of working it out yourself, e.g. 38*60 for 38 minutes in seconds.",
                           schema: #"{"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}"#),
        ]
    }

    public func call(_ name: String, arguments: Data) async throws -> String {
        guard name == "calculate" else { throw ChatError("No tool named \(name).") }
        let input = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        let expression = (input["expression"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return "\(expression) = \(Self.format(try Self.evaluate(expression)))"
    }

    /// Whole numbers without a decimal point, others to at most 6 decimals: 2280, 0.333333, 12.5.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Recursive descent over  sum := product (('+'|'-') product)*,  product := power (('*'|'/') power)*,
    /// power := unary ('^' power)?,  unary := '-' unary | atom '%'?,  atom := number | '(' sum ')'.
    /// Refuses anything else, so a bad call gets an error to fix rather than a wrong number.
    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(expression)
        let value = try parser.sum()
        guard parser.atEnd else { throw ChatError("Couldn't read \"\(expression)\": use numbers, + - * / ^ % and brackets.") }
        guard value.isFinite else { throw ChatError("That has no finite answer (dividing by zero?).") }
        return value
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0
        private let original: String

        init(_ text: String) {
            original = text
            // "1,000" and "×" are fine to write; spaces are ignored.
            chars = Array(text.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/").filter { !$0.isWhitespace })
        }

        var atEnd: Bool { index == chars.count }

        private var bad: ChatError { ChatError("Couldn't read \"\(original)\": use numbers, + - * / ^ % and brackets.") }

        private mutating func take(_ char: Character) -> Bool {
            guard index < chars.count, chars[index] == char else { return false }
            index += 1
            return true
        }

        mutating func sum() throws -> Double {
            var value = try product()
            while true {
                if take("+") { value += try product() } else if take("-") { value -= try product() } else { return value }
            }
        }

        mutating func product() throws -> Double {
            var value = try power()
            while true {
                if take("*") { value *= try power() } else if take("/") { value /= try power() } else { return value }
            }
        }

        mutating func power() throws -> Double {
            let base = try unary()
            return take("^") ? pow(base, try power()) : base
        }

        mutating func unary() throws -> Double {
            if take("-") { return -(try unary()) }
            if take("+") { return try unary() }
            let value = try atom()
            return take("%") ? value / 100 : value
        }

        mutating func atom() throws -> Double {
            if take("(") {
                let value = try sum()
                guard take(")") else { throw bad }
                return value
            }
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." { index += 1 }
            guard index > start, let value = Double(String(chars[start..<index])) else { throw bad }
            return value
        }
    }
}
