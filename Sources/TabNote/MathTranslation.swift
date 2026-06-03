// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

@MainActor
func createMathImage(for markdown: String) -> NSImage? {
    var processed = markdown
    if processed.hasPrefix("$") && processed.hasSuffix("$") && !processed.hasPrefix("$$") {
        processed = "\\(" + processed.dropFirst().dropLast() + "\\)"
    } else if processed.hasPrefix("$$") && processed.hasSuffix("$$") {
        processed = "\\[" + processed.dropFirst(2).dropLast(2) + "\\]"
    }

    // Use slightly larger font to match surrounding 18pt system text
    // (LaTeX rendering is visually smaller than system font at same pt size)
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

// MARK: - LaTeX Editing Popover View

struct LocalMathTranslator {
    static let greekLetters = [
        "alpha": "\\alpha", "beta": "\\beta", "gamma": "\\gamma", "delta": "\\delta",
        "epsilon": "\\epsilon", "theta": "\\theta", "lambda": "\\lambda", "mu": "\\mu",
        "sigma": "\\sigma", "omega": "\\omega", "phi": "\\phi", "psi": "\\psi",
        "tau": "\\tau", "rho": "\\rho", "pi": "\\pi", "infinity": "\\infty", "infty": "\\infty"
    ]

    static func translate(text: String) -> (original: String, latex: String)? {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return nil
        }
        
        // 1. Integrals: "integral from X to Y of Z" -> \int_{X}^{Y} Z
        let integralPattern = "(?i)\\bintegral\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: integralPattern, in: lastLine) {
            let original = match[0]
            let fromVal = cleanExpr(match[1])
            let toVal = cleanExpr(match[2])
            let ofVal = cleanExpr(match[3])
            let latex = "\\( \\int_{\(fromVal)}^{\(toVal)} \(ofVal) \\)"
            return (original, latex)
        }
        
        // 2. Sums: "sum of X from Y to Z"
        let sumPattern1 = "(?i)\\bsum\\s+of\\s+(.+?)\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)$"
        if let match = matchRegex(pattern: sumPattern1, in: lastLine) {
            let original = match[0]
            let expr = cleanExpr(match[1])
            let fromVal = cleanExpr(match[2])
            let toVal = cleanExpr(match[3])
            let latex = "\\( \\sum_{\(fromVal)}^{\(toVal)} \(expr) \\)"
            return (original, latex)
        }
        
        // "sum from Y to Z of X"
        let sumPattern2 = "(?i)\\bsum\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: sumPattern2, in: lastLine) {
            let original = match[0]
            let fromVal = cleanExpr(match[1])
            let toVal = cleanExpr(match[2])
            let expr = cleanExpr(match[3])
            let latex = "\\( \\sum_{\(fromVal)}^{\(toVal)} \(expr) \\)"
            return (original, latex)
        }
        
        // 3. Limits: "limit as X approaches Y of Z"
        let limitPattern = "(?i)\\blimit\\s+as\\s+(\\S+)\\s+approaches\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: limitPattern, in: lastLine) {
            let original = match[0]
            let varVal = cleanExpr(match[1])
            let approachVal = cleanExpr(match[2])
            let expr = cleanExpr(match[3])
            let latex = "\\( \\lim_{\(varVal) \\to \(approachVal)} \(expr) \\)"
            return (original, latex)
        }

        // 4. Fractions: "X over Y" or "X divided by Y"
        let overPattern = "(?i)\\b(.+?)\\s+over\\s+(.+)$"
        if let match = matchRegex(pattern: overPattern, in: lastLine) {
            let original = match[0]
            let num = cleanExpr(match[1])
            let den = cleanExpr(match[2])
            let latex = "\\( \\frac{\(num)}{\(den)} \\)"
            return (original, latex)
        }
        
        // 5. General formulas / equations
        if mightBeMathLine(lastLine) {
            let latex = cleanExpr(lastLine)
            if latex.lowercased() != lastLine.lowercased() {
                let mathWords = ["pi", "squared", "cubed", "plus", "minus", "equals", "times", "dot", "cross", "alpha", "beta", "gamma", "delta", "epsilon", "theta", "lambda", "mu", "sigma", "omega", "phi", "psi", "tau", "rho", "infinity", "vector", "matrix", "sqrt", "root"]
                let words = lastLine.components(separatedBy: .whitespaces)
                var mathStartIndex = words.count - 1
                for (idx, word) in words.enumerated() {
                    let lowerWord = word.lowercased()
                    let cleanWord = lowerWord.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
                    if mathWords.contains(cleanWord)
                        || lowerWord.rangeOfCharacter(from: .decimalDigits) != nil
                        || lowerWord.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^=<>()_")) != nil {
                        mathStartIndex = idx
                        break
                    }
                }
                
                // Backtrack to include preceding single-character variables or simple math terms
                while mathStartIndex > 0 {
                    let prevWord = words[mathStartIndex - 1]
                    let cleanPrev = prevWord.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
                    if cleanPrev.count == 1 || mathWords.contains(cleanPrev.lowercased()) {
                        mathStartIndex -= 1
                    } else {
                        break
                    }
                }
                
                let original = words[mathStartIndex...].joined(separator: " ")
                let cleanMath = cleanExpr(original)
                return (original, "\\( \(cleanMath) \\)")
            }
        }
        
        return nil
    }
    
    private static func mightBeMathLine(_ line: String) -> Bool {
        let mathKeywords = ["squared", "cubed", "plus", "minus", "equals", "times", "dot", "cross", "over", "sum", "integral", "limit", "vector", "matrix", "sqrt", "root"]
        let lower = line.lowercased()
        for kw in mathKeywords {
            if lower.contains(kw) { return true }
        }
        for greek in greekLetters.keys {
            if lower.contains(greek) { return true }
        }
        let mathChars = CharacterSet(charactersIn: "+-*/^=<>()_")
        if lower.rangeOfCharacter(from: mathChars) != nil {
            return true
        }
        return false
    }

    private static func cleanExpr(_ expr: String) -> String {
        var result = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Handle "square root of X" -> \sqrt{X}
        let sqrtPattern = "(?i)\\bsquare\\s+root\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: sqrtPattern, in: result) {
            let inner = cleanExpr(match[1])
            result = result.replacingOccurrences(of: match[0], with: "\\sqrt{\(inner)}")
        }
        
        // 2. Handle "vector X" -> \mathbf{X}
        let vectorPattern = "(?i)\\bvector\\s+([a-zA-Z0-9]+)"
        while let match = matchRegex(pattern: vectorPattern, in: result) {
            let inner = match[1]
            result = result.replacingOccurrences(of: match[0], with: "\\mathbf{\(inner)}")
        }

        // 3. Handle nested "over" inside cleanExpr
        let overPattern = "(?i)\\b(.+?)\\s+over\\s+(.+)$"
        if let match = matchRegex(pattern: overPattern, in: result) {
            let num = cleanExpr(match[1])
            let den = cleanExpr(match[2])
            result = result.replacingOccurrences(of: match[0], with: "\\frac{\(num)}{\(den)}")
        }

        // Tokenize into words and convert
        var tokens = result.components(separatedBy: .whitespaces)
        var i = 0
        while i < tokens.count {
            let token = tokens[i].lowercased()
            
            // Check for greek letters
            if let latexGreek = greekLetters[token] {
                tokens[i] = latexGreek
            }
            // Check for simple operators
            else if token == "plus" || token == "+" {
                tokens[i] = "+"
            } else if token == "minus" || token == "-" {
                tokens[i] = "-"
            } else if token == "equals" || token == "=" {
                tokens[i] = "="
            } else if token == "dot" || token == "times" {
                tokens[i] = "\\cdot"
            } else if token == "cross" {
                tokens[i] = "\\times"
            }
            // Exponents
            else if token == "squared" {
                if i > 0 {
                    tokens[i-1] = tokens[i-1] + "^2"
                    tokens.remove(at: i)
                    continue
                }
            } else if token == "cubed" {
                if i > 0 {
                    tokens[i-1] = tokens[i-1] + "^3"
                    tokens.remove(at: i)
                    continue
                }
            }
            // Subscripts: "x sub i" -> "x_i"
            else if token == "sub" || token == "subscript" {
                if i > 0 && i < tokens.count - 1 {
                    let next = tokens[i+1]
                    tokens[i-1] = tokens[i-1] + "_\(next)"
                    tokens.remove(at: i + 1)
                    tokens.remove(at: i)
                    continue
                }
            }
            
            i += 1
        }
        
        result = tokens.joined(separator: " ")
        
        // Post-processing cleanup for spacing
        // e.g. "a ^ 2" -> "a^2"
        result = result.replacingOccurrences(of: " \\^ ", with: "^")
        result = result.replacingOccurrences(of: "\\^ ", with: "^")
        result = result.replacingOccurrences(of: " \\^", with: "^")
        
        // variables with digits -> subscript, e.g. "t1" -> "t_1"
        result = result.replacingOccurrences(of: "\\b([a-zA-Z])(\\d+)\\b", with: "$1_$2", options: .regularExpression)
        
        // fractions like "1/2" -> "\frac{1}{2}"
        let fracPattern = "(\\d+)/(\\d+)"
        if let regex = try? NSRegularExpression(pattern: fracPattern) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let num = ns.substring(with: m.range(at: 1))
                let den = ns.substring(with: m.range(at: 2))
                result = ns.replacingCharacters(in: m.range, with: "\\frac{\(num)}{\(den)}")
            }
        }
        
        return result
    }

    private static func matchRegex(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        
        var results = [String]()
        results.append(ns.substring(with: match.range(at: 0)))
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound {
                results.append(ns.substring(with: r))
            } else {
                results.append("")
            }
        }
        return results
    }
}

