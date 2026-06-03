import Foundation

let prefix = "The kinetic energy ke is 1/2mv^2 and the work w is "
let originalText = "1/2mv^2"

let core = originalText.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
let prefixString = prefix.lowercased()

// Find the last occurrence of core in the prefix, ignoring whitespaces in the prefix
var prefixChars = Array(prefix)
var coreChars = Array(core)

var matchStart = -1
var matchEnd = -1

var pIndex = prefixChars.count - 1
while pIndex >= 0 {
    if prefixChars[pIndex].isWhitespace {
        pIndex -= 1
        continue
    }
    
    if prefixChars[pIndex].lowercased() == String(coreChars.last!) {
        // Potential match, trace backwards
        var cIndex = coreChars.count - 1
        var tempPIndex = pIndex
        var matched = true
        
        while cIndex >= 0 && tempPIndex >= 0 {
            if prefixChars[tempPIndex].isWhitespace {
                tempPIndex -= 1
                continue
            }
            if prefixChars[tempPIndex].lowercased() == String(coreChars[cIndex]) {
                cIndex -= 1
                tempPIndex -= 1
            } else {
                matched = false
                break
            }
        }
        
        if cIndex < 0 {
            // Found a match!
            matchStart = tempPIndex + 1
            matchEnd = pIndex
            break
        }
    }
    pIndex -= 1
}

if matchStart != -1 {
    print("Match found from \(matchStart) to \(matchEnd)")
    let matchStr = String(prefixChars[matchStart...matchEnd])
    print("Matched string: '\(matchStr)'")
} else {
    print("No match found")
}

