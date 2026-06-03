import Foundation

let rawSuggestion = "<original>x ^2 + y^2 = 5</original><latex>\\( x^2 + y^2 = 5 \\)</latex>"
let prefix = "Here is the math x ^2 + y^2 = 5"

let pattern = "<original>(.*?)</original>\\s*<latex>(.*?)</latex>"
if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
   let match = regex.firstMatch(in: rawSuggestion, range: NSRange(rawSuggestion.startIndex..., in: rawSuggestion)) {
    
    let nsString = rawSuggestion as NSString
    let originalText = nsString.substring(with: match.range(at: 1))
    let latexText = nsString.substring(with: match.range(at: 2))
    
    let core = originalText.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
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
                print("SUCCESS: matchCount = \(matchCount), latex = \(latexText)")
                exit(0)
            }
            coreIndex = core.index(before: coreIndex)
        } else {
            print("FAILED at prefix index \(i), char: \(c), expected: \(core[coreIndex])")
            break
        }
    }
}
print("FAILED ENTIRELY")
