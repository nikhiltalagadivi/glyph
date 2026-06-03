import Foundation

let prefix = "integral of x from 0 to infinity"
let originalText = "integral of x from 0 to infinity"
let latexText = "latex_here"

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
    if coreIndex >= core.startIndex && c.lowercased() == String(core[coreIndex]).lowercased() {
        matchCount += 1
        if coreIndex == core.startIndex {
            print("MATCH! replaceLength: \\(matchCount)")
            exit(0)
        }
        coreIndex = core.index(before: coreIndex)
    } else {
        print("MISMATCH at c='\\(c)', core='\\(core[coreIndex])'")
        break
    }
}
print("FAILED")
