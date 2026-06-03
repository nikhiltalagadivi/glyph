// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// MARK: - Math Image Renderer

@MainActor
func createMathImage(for markdown: String) -> NSImage? {
    // Normalise delimiter styles to \(...\) / \[...\]
    let processed: String
    if markdown.hasPrefix("$$"), markdown.hasSuffix("$$") {
        processed = "\\[" + markdown.dropFirst(2).dropLast(2) + "\\]"
    } else if markdown.hasPrefix("$"), markdown.hasSuffix("$") {
        processed = "\\(" + markdown.dropFirst().dropLast() + "\\)"
    } else {
        // Already in \(...\) or \[...\] form — pass through
        processed = markdown
    }

    // Render at 20pt to match the visual weight of the surrounding 18pt system font
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(.black)
        .fixedSize()

    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let img = renderer.nsImage
    img?.isTemplate = true
    return img
}

// MARK: - Regex Cache

/// Thread-safe, lazily-populated regex cache. Avoids recompiling the same pattern
/// on every keystroke — particularly important inside tight translation loops.
private final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        cache[pattern] = re
        return re
    }
}

// MARK: - LocalMathTranslator

/// Translates natural-language math phrases into LaTeX markup.
/// All methods are pure functions — no mutable state.
enum LocalMathTranslator {

    // MARK: Greek letters & common symbols

    static let greekLetters: [String: String] = [
        "alpha": "\\alpha",   "beta": "\\beta",     "gamma": "\\gamma",
        "delta": "\\delta",   "epsilon": "\\epsilon","zeta": "\\zeta",
        "eta": "\\eta",       "theta": "\\theta",    "iota": "\\iota",
        "kappa": "\\kappa",   "lambda": "\\lambda",  "mu": "\\mu",
        "nu": "\\nu",         "xi": "\\xi",          "pi": "\\pi",
        "rho": "\\rho",       "sigma": "\\sigma",    "tau": "\\tau",
        "upsilon": "\\upsilon","phi": "\\phi",        "chi": "\\chi",
        "psi": "\\psi",       "omega": "\\omega",
        // Capitals
        "Gamma": "\\Gamma",   "Delta": "\\Delta",    "Theta": "\\Theta",
        "Lambda": "\\Lambda", "Xi": "\\Xi",          "Pi": "\\Pi",
        "Sigma": "\\Sigma",   "Upsilon": "\\Upsilon", "Phi": "\\Phi",
        "Psi": "\\Psi",       "Omega": "\\Omega",
        // Common aliases
        "infinity": "\\infty", "infty": "\\infty",
        "partial": "\\partial", "nabla": "\\nabla",
        "hbar": "\\hbar"
    ]

    // MARK: Public entry point

    /// Examines the last non-empty line of `text` and attempts to identify and
    /// translate a mathematical phrase. Returns `(originalFragment, latex)` on
    /// success, or `nil` if no mathematical content is detected.
    static func translate(text: String) -> (original: String, latex: String)? {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return nil
        }
        return matchStructured(lastLine) ?? matchGeneral(lastLine)
    }

    // MARK: - Structured Pattern Matching

    private static func matchStructured(_ line: String) -> (String, String)? {
        // 1. Integral: "integral from X to Y of Z"
        let integralPat = "(?i)\\bintegral\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let m = match(integralPat, in: line) {
            let latex = "\\( \\int_{\(clean(m[1]))}^{\(clean(m[2]))} \(clean(m[3])) \\, d\(inferDifferential(m[3])) \\)"
            return (m[0], latex)
        }

        // 2a. Sum: "sum of X from Y to Z"
        let sumPat1 = "(?i)\\bsum\\s+of\\s+(.+?)\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)$"
        if let m = match(sumPat1, in: line) {
            let latex = "\\( \\sum_{\(clean(m[2]))}^{\(clean(m[3]))} \(clean(m[1])) \\)"
            return (m[0], latex)
        }

        // 2b. Sum: "sum from Y to Z of X"
        let sumPat2 = "(?i)\\bsum\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let m = match(sumPat2, in: line) {
            let latex = "\\( \\sum_{\(clean(m[1]))}^{\(clean(m[2]))} \(clean(m[3])) \\)"
            return (m[0], latex)
        }

        // 3. Product: "product from Y to Z of X" / "product of X from Y to Z"
        let prodPat1 = "(?i)\\bproduct\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let m = match(prodPat1, in: line) {
            let latex = "\\( \\prod_{\(clean(m[1]))}^{\(clean(m[2]))} \(clean(m[3])) \\)"
            return (m[0], latex)
        }

        // 4. Limit: "limit as X approaches Y of Z"
        let limitPat = "(?i)\\blimit\\s+as\\s+(\\S+)\\s+approaches\\s+(\\S+(?:\\s+\\S+)?)\\s+of\\s+(.+)$"
        if let m = match(limitPat, in: line) {
            let approach = clean(m[2])  // handles "positive infinity" etc.
            let latex = "\\( \\lim_{\(clean(m[1])) \\to \(approach)} \(clean(m[3])) \\)"
            return (m[0], latex)
        }

        // 5. Derivative: "derivative of X with respect to Y"
        let derivPat = "(?i)\\bderivative\\s+of\\s+(.+?)\\s+with\\s+respect\\s+to\\s+(\\S+)$"
        if let m = match(derivPat, in: line) {
            let latex = "\\( \\frac{d\(clean(m[1]))}{d\(clean(m[2]))} \\)"
            return (m[0], latex)
        }

        // 6. Partial derivative: "partial derivative of X with respect to Y"
        let partialPat = "(?i)\\bpartial\\s+derivative\\s+of\\s+(.+?)\\s+with\\s+respect\\s+to\\s+(\\S+)$"
        if let m = match(partialPat, in: line) {
            let latex = "\\( \\frac{\\partial \(clean(m[1]))}{\\partial \(clean(m[2]))} \\)"
            return (m[0], latex)
        }

        // 7. Fraction: "X over Y" / "X divided by Y"
        let overPat = "(?i)\\b(.+?)\\s+(?:over|divided by)\\s+(.+)$"
        if let m = match(overPat, in: line) {
            let latex = "\\( \\frac{\(clean(m[1]))}{\(clean(m[2]))} \\)"
            return (m[0], latex)
        }

        // 8. N-th root: "nth root of X" / "cube root of X"
        let nthRootPat = "(?i)\\b(\\w+)\\s+root\\s+of\\s+(.+)$"
        if let m = match(nthRootPat, in: line) {
            let index = ordinalToInt(m[1])
            let inner = clean(m[2])
            let latex = index == 2
                ? "\\( \\sqrt{\(inner)} \\)"
                : "\\( \\sqrt[\(index)]{\(inner)} \\)"
            return (m[0], latex)
        }

        // 9. Absolute value: "absolute value of X" / "abs X"
        let absPat = "(?i)\\b(?:absolute value of|abs)\\s+(.+)$"
        if let m = match(absPat, in: line) {
            let latex = "\\( \\left| \(clean(m[1])) \\right| \\)"
            return (m[0], latex)
        }

        // 10. Floor / ceiling
        let floorPat = "(?i)\\bfloor(?:\\s+of)?\\s+(.+)$"
        if let m = match(floorPat, in: line) {
            let latex = "\\( \\lfloor \(clean(m[1])) \\rfloor \\)"
            return (m[0], latex)
        }
        let ceilPat = "(?i)\\bceil(?:ing)?(?:\\s+of)?\\s+(.+)$"
        if let m = match(ceilPat, in: line) {
            let latex = "\\( \\lceil \(clean(m[1])) \\rceil \\)"
            return (m[0], latex)
        }

        // 11. Trig / log / exp: "sin of X", "log base 2 of X", "exp of X"
        let trigPat = "(?i)\\b(sin|cos|tan|cot|sec|csc|arcsin|arccos|arctan|sinh|cosh|tanh|exp|ln)\\s+of\\s+(.+)$"
        if let m = match(trigPat, in: line) {
            let latex = "\\( \\\(m[1].lowercased()){\(clean(m[2]))} \\)"
            return (m[0], latex)
        }
        let logBasePat = "(?i)\\blog\\s+base\\s+(\\S+)\\s+of\\s+(.+)$"
        if let m = match(logBasePat, in: line) {
            let latex = "\\( \\log_{\(clean(m[1]))} \(clean(m[2])) \\)"
            return (m[0], latex)
        }

        // 12. Norm: "norm of X"
        let normPat = "(?i)\\bnorm\\s+of\\s+(.+)$"
        if let m = match(normPat, in: line) {
            let latex = "\\( \\left\\| \(clean(m[1])) \\right\\| \\)"
            return (m[0], latex)
        }

        return nil
    }

    // MARK: - General Formula Heuristic

    private static func matchGeneral(_ line: String) -> (String, String)? {
        guard mightBeMathLine(line) else { return nil }
        let latex = clean(line)
        guard latex != line else { return nil }

        // Walk words from left until we hit clear math content
        let words = line.components(separatedBy: .whitespaces)
        let mathStart = findMathStart(in: words)
        let original = words[mathStart...].joined(separator: " ")
        return (original, "\\( \(clean(original)) \\)")
    }

    // MARK: - Helpers

    private static func mightBeMathLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let mathKeywords = [
            "squared", "cubed", "plus", "minus", "equals", "times", "dot", "cross",
            "over", "sum", "integral", "limit", "vector", "matrix", "sqrt", "root",
            "norm", "abs", "floor", "ceil", "derivative", "partial", "product",
            "sin", "cos", "tan", "log", "exp", "ln"
        ]
        if mathKeywords.contains(where: { lower.contains($0) }) { return true }
        if greekLetters.keys.contains(where: { lower.contains($0) }) { return true }
        let mathChars = CharacterSet(charactersIn: "+-*/^=<>()_|")
        return lower.rangeOfCharacter(from: mathChars) != nil
    }

    private static func findMathStart(in words: [String]) -> Int {
        let mathWords: Set<String> = [
            "pi", "squared", "cubed", "plus", "minus", "equals", "times",
            "dot", "cross", "alpha", "beta", "gamma", "delta", "epsilon",
            "theta", "lambda", "mu", "sigma", "omega", "phi", "psi",
            "tau", "rho", "infinity", "vector", "matrix", "sqrt", "root",
            "norm", "abs", "floor", "ceil", "sin", "cos", "tan", "log", "exp", "ln"
        ]
        let mathChars = CharacterSet(charactersIn: "+-*/^=<>()_|")

        var start = words.count - 1
        for (idx, word) in words.enumerated() {
            let clean = word.lowercased()
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
            if mathWords.contains(clean)
                || clean.rangeOfCharacter(from: .decimalDigits) != nil
                || clean.rangeOfCharacter(from: mathChars) != nil {
                start = idx
                break
            }
        }

        // Backtrack to include preceding single-char variables
        while start > 0 {
            let prev = words[start - 1]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
            if prev.count == 1 || mathWords.contains(prev.lowercased()) {
                start -= 1
            } else {
                break
            }
        }
        return start
    }

    /// Attempts to infer the differential variable from an integrand expression.
    /// e.g. "f(x)" → "x", "g(t)" → "t", "h(x, y)" → "x", fallback → "x"
    private static func inferDifferential(_ integrand: String) -> String {
        if let m = match("\\(([a-zA-Z])", in: integrand) { return m[1] }
        // Last single letter in the expression
        let letters = integrand.unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map { String($0) }
        return letters.last ?? "x"
    }

    /// Converts ordinal/number words to Int. "cube" → 3, "fourth" → 4, etc.
    private static func ordinalToInt(_ word: String) -> Int {
        switch word.lowercased() {
        case "square", "second": return 2
        case "cube", "cubic", "third": return 3
        case "fourth", "quartic": return 4
        case "fifth": return 5
        case "sixth": return 6
        case "seventh": return 7
        case "eighth": return 8
        default:
            // Try parsing a bare numeral: "5th", "5" → 5
            let digits = word.filter(\.isNumber)
            return Int(digits) ?? 2
        }
    }

    // MARK: - Expression Cleaner

    /// Recursively converts a natural-language math fragment to LaTeX tokens.
    static func clean(_ expr: String) -> String {
        var result = expr.trimmingCharacters(in: .whitespacesAndNewlines)

        // --- Structural patterns (highest priority, applied first) ---

        // "square root of X" / "sqrt X"
        let sqrtPat = "(?i)\\bsquare\\s+root\\s+of\\s+(.+)$"
        if let m = match(sqrtPat, in: result) {
            result = result.replacingOccurrences(of: m[0], with: "\\sqrt{\(clean(m[1]))}")
        }

        // "n-th root of X"
        let nthRootPat = "(?i)\\b(\\w+)\\s+root\\s+of\\s+(.+)$"
        if let m = match(nthRootPat, in: result) {
            let n = ordinalToInt(m[1])
            let inner = clean(m[2])
            result = result.replacingOccurrences(
                of: m[0],
                with: n == 2 ? "\\sqrt{\(inner)}" : "\\sqrt[\(n)]{\(inner)}"
            )
        }

        // "vector X" → \mathbf{X}  (replace all occurrences)
        let vecPat = "(?i)\\bvector\\s+([a-zA-Z0-9]+)"
        while let m = match(vecPat, in: result) {
            result = result.replacingOccurrences(of: m[0], with: "\\mathbf{\(m[1])}")
        }

        // "X over Y"
        let overPat = "(?i)\\b(.+?)\\s+over\\s+(.+)$"
        if let m = match(overPat, in: result) {
            result = result.replacingOccurrences(
                of: m[0],
                with: "\\frac{\(clean(m[1]))}{\(clean(m[2]))}"
            )
        }

        // --- Token-level substitutions ---
        var tokens = result.components(separatedBy: .whitespaces)
        var i = 0
        while i < tokens.count {
            let lower = tokens[i].lowercased()

            if let greek = greekLetters[lower] {
                tokens[i] = greek
            } else if let greek = greekLetters[tokens[i]] { // case-sensitive capitals
                tokens[i] = greek
            } else {
                switch lower {
                case "plus":                tokens[i] = "+"
                case "minus":               tokens[i] = "-"
                case "equals":              tokens[i] = "="
                case "times", "dot":        tokens[i] = "\\cdot"
                case "cross":               tokens[i] = "\\times"
                case "infinity", "infty":   tokens[i] = "\\infty"
                case "partial":             tokens[i] = "\\partial"
                case "nabla":               tokens[i] = "\\nabla"
                case "squared":
                    if i > 0 { tokens[i-1] += "^2"; tokens.remove(at: i); continue }
                case "cubed":
                    if i > 0 { tokens[i-1] += "^3"; tokens.remove(at: i); continue }
                case "sub", "subscript":
                    if i > 0, i < tokens.count - 1 {
                        tokens[i-1] += "_{\(tokens[i+1])}"
                        tokens.remove(at: i + 1)
                        tokens.remove(at: i)
                        continue
                    }
                case "to", "approaches":    tokens[i] = "\\to"
                case "not":
                    if i < tokens.count - 1 {
                        tokens[i+1] = "\\not\(tokens[i+1])"
                        tokens.remove(at: i)
                        continue
                    }
                default: break
                }
            }
            i += 1
        }
        result = tokens.joined(separator: " ")

        // --- Post-processing ---

        // Remove stray spaces around ^ and _
        result = result
            .replacingOccurrences(of: " ^ ", with: "^")
            .replacingOccurrences(of: "^ ", with: "^")
            .replacingOccurrences(of: " ^", with: "^")
            .replacingOccurrences(of: " _ ", with: "_")

        // "a1" → "a_1" (single-letter variable followed by digit)
        result = result.replacingOccurrences(
            of: "\\b([a-zA-Z])(\\d+)\\b",
            with: "$1_$2",
            options: .regularExpression
        )

        // "1/2" → "\frac{1}{2}"
        if let re = RegexCache.shared.regex(for: "(\\d+)/(\\d+)") {
            let ns = result as NSString
            let matches = re.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let num = ns.substring(with: m.range(at: 1))
                let den = ns.substring(with: m.range(at: 2))
                result = (result as NSString).replacingCharacters(in: m.range, with: "\\frac{\(num)}{\(den)}")
            }
        }

        // "positive infinity" / "negative infinity" → +\infty / -\infty
        result = result
            .replacingOccurrences(of: "(?i)positive\\s+\\\\infty", with: "+\\infty", options: .regularExpression)
            .replacingOccurrences(of: "(?i)negative\\s+\\\\infty", with: "-\\infty", options: .regularExpression)
            .replacingOccurrences(of: "(?i)positive\\s+infinity", with: "+\\infty", options: .regularExpression)
            .replacingOccurrences(of: "(?i)negative\\s+infinity", with: "-\\infty", options: .regularExpression)

        return result
    }

    // MARK: - Regex Matching (cached)

    /// Returns capture groups [fullMatch, group1, group2, …] or nil.
    static func match(_ pattern: String, in text: String) -> [String]? {
        guard let re = RegexCache.shared.regex(for: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location != NSNotFound ? ns.substring(with: r) : ""
        }
    }
}
