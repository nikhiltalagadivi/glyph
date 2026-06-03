import Foundation

let prefix = "The kinetic energy ke is 1/2mv^2 and the work w is "
let originalText = "1/2mv^2"

let core = originalText.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
let nsPrefix = prefix as NSString

var pIndex = nsPrefix.length - 1
var coreChars = Array(core)

var matchStart = -1
var matchEnd = -1

while pIndex >= 0 {
    let charStr = nsPrefix.substring(with: NSRange(location: pIndex, length: 1))
    if charStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        pIndex -= 1
        continue
    }
    
    if charStr.lowercased() == String(coreChars.last!) {
        var cIndex = coreChars.count - 1
        var tempPIndex = pIndex
        
        while cIndex >= 0 && tempPIndex >= 0 {
            let tempCharStr = nsPrefix.substring(with: NSRange(location: tempPIndex, length: 1))
            if tempCharStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tempPIndex -= 1
                continue
            }
            if tempCharStr.lowercased() == String(coreChars[cIndex]) {
                cIndex -= 1
                tempPIndex -= 1
            } else {
                break
            }
        }
        
        if cIndex < 0 {
            matchStart = tempPIndex + 1
            matchEnd = pIndex
            break
        }
    }
    pIndex -= 1
}

if matchStart != -1 {
    let range = NSRange(location: matchStart, length: matchEnd - matchStart + 1)
    print("Matched range: \(range)")
    print("Matched string: '\(nsPrefix.substring(with: range))'")
} else {
    print("No match found")
}

