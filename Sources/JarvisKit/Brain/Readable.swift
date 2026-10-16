import Foundation

/// Makes a model's answer fit a caption and a voice: LaTeX becomes plain maths (x², √2, a/b, π),
/// and markdown marks (**bold**, # headings, `code`) are dropped. Models are asked not to use them;
/// this catches what slips through.
public enum Readable {
    private static let symbols: [String: String] = [
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥",
        "ne": "≠", "neq": "≠", "approx": "≈", "equiv": "≡", "infty": "∞", "to": "→", "rightarrow": "→",
        "Rightarrow": "⇒", "leftarrow": "←", "implies": "⇒", "in": "∈", "notin": "∉", "subset": "⊂", "cup": "∪",
        "cap": "∩", "sum": "∑", "prod": "∏", "int": "∫", "partial": "∂", "nabla": "∇", "degree": "°", "circ": "°",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "Delta": "Δ", "epsilon": "ε", "theta": "θ",
        "lambda": "λ", "mu": "μ", "pi": "π", "rho": "ρ", "sigma": "σ", "Sigma": "Σ", "tau": "τ", "phi": "φ",
        "omega": "ω", "Omega": "Ω", "ldots": "…", "cdots": "…", "dots": "…", "quad": " ", "qquad": " ",
        "left": "", "right": "", "displaystyle": "", ",": " ", ";": " ", "!": "",
    ]
    private static let superscripts = Dictionary(uniqueKeysWithValues: zip("0123456789+-=()n", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ"))
    private static let subscripts = Dictionary(uniqueKeysWithValues: zip("0123456789+-=()", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎"))

    public static func clean(_ text: String) -> String {
        var s = text
        // Maths delimiters: $$..$$, \[..\], \(..\), $..$ (not prices like "$5 and $10").
        for pattern in [#"\$\$(.+?)\$\$"#, #"\\\[(.+?)\\\]"#, #"\\\((.+?)\\\)"#, #"(?<![\w\\])\$(?!\d)([^$\n]+?)\$"#] {
            s = replace(s, pattern, dotAll: true) { latex($0[1]) }
        }
        if s.contains("\\") { s = latex(s) }
        // Notion ids and block ids are for the tools, not for reading or saying aloud.
        s = replace(s, #"\s*\(block [0-9a-fA-F-]+\)"#) { _ in "" }
        s = replace(s, #",\s*id [0-9a-fA-F-]{2,}"#) { _ in "" }
        s = replace(s, #"\s*\(id [0-9a-fA-F-]{2,}\)"#) { _ in "" }
        // Markdown: headings, bold/italic, inline code, bullets.
        s = replace(s, #"(?m)^\s{0,3}#{1,6}\s+"#) { _ in "" }
        s = replace(s, #"\*\*(.+?)\*\*"#) { $0[1] }
        s = replace(s, #"__(.+?)__"#) { $0[1] }
        s = replace(s, #"(?<![\w*])\*([^*\n]+?)\*(?![\w*])"#) { $0[1] }
        s = replace(s, #"`([^`]+)`"#) { $0[1] }
        s = replace(s, #"(?m)^[ \t]*[-*•][ \t]+"#) { _ in "• " }
        s = replace(s, #"[ \t]{2,}"#) { _ in " " }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One piece of LaTeX as plain text.
    static func latex(_ input: String) -> String {
        var s = input
        // Run until stable so nested pieces (\frac{\sqrt{2}}{2}) unwrap from the inside out.
        for _ in 0..<6 {
            let before = s
            s = replace(s, #"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}"#) { "\(group($0[1]))/\(group($0[2]))" }
            s = replace(s, #"\\sqrt\[([^\]]*)\]\{([^{}]*)\}"#) { "\($0[1])√\(group($0[2]))" }
            s = replace(s, #"\\sqrt\{([^{}]*)\}"#) { "√\(group($0[1]))" }
            s = replace(s, #"\\(?:text|mathrm|mathbf|mathit|operatorname|textbf|boldsymbol|vec|hat|bar)\{([^{}]*)\}"#) { $0[1] }
            s = replace(s, #"\^\{([^{}]*)\}"#) { raise($0[1], superscripts, "^") }
            s = replace(s, #"_\{([^{}]*)\}"#) { raise($0[1], subscripts, "_") }
            if s == before { break }
        }
        s = replace(s, #"\^([0-9n+\-])"#) { raise($0[1], superscripts, "^") }
        s = replace(s, #"_([0-9])"#) { raise($0[1], subscripts, "_") }
        s = replace(s, #"\\([A-Za-z]+|[,;!])"#) { symbols[$0[1]] ?? $0[1] }
        return replace(s, #"[{}]"#) { _ in "" }
    }

    /// x^{2} -> x², or x^(a+b) when there's no superscript for every character.
    private static func raise(_ text: String, _ table: [Character: Character], _ mark: String) -> String {
        let mapped = text.compactMap { table[$0] }
        return mapped.count == text.count ? String(mapped) : "\(mark)(\(text))"
    }

    /// Brackets a fraction's part when it has more than one term: (a+b)/2.
    private static func group(_ part: String) -> String {
        part.contains(where: { "+-− ".contains($0) }) ? "(\(part))" : part
    }

    /// Regex replace where `transform` gets the match and its groups as strings.
    private static func replace(_ text: String, _ pattern: String, dotAll: Bool = false,
                                _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: dotAll ? .dotMatchesLineSeparators : []) else {
            return text
        }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            result.replaceSubrange(whole, with: transform(groups))
        }
        return result
    }
}
