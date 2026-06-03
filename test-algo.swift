import Foundation

func computeLength(latex: String, prefix: String) -> Int {
    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("\\(") && trimmed.hasSuffix("\\)") {
        let core = trimmed.dropFirst(2).dropLast(2)
                          .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let prefixChars = Array(prefix)
        var coreIndex = core.index(before: core.endIndex)
        var matchCount = 0
        
        for i in stride(from: prefixChars.count - 1, through: 0, by: -1) {
            let c = prefixChars[i]
            if c.isWhitespace {
                matchCount += 1
                continue
            }
            if coreIndex >= core.startIndex && c == core[coreIndex] {
                matchCount += 1
                if coreIndex == core.startIndex {
                    return matchCount
                }
                coreIndex = core.index(before: coreIndex)
            } else {
                break
            }
        }
    }
    return 0
}

print(computeLength(latex: "\\( x^2 + y^2 = 5 \\)", prefix: "The equation is x ^2 + y^2 = 5"))
print(computeLength(latex: "\\( x^2 + y^2 = 5 \\)", prefix: "x ^2 + y^2 = 5"))
print(computeLength(latex: "\\( \\pi r^2 \\)", prefix: "The area of a circle is pi r squared"))
