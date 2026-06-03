import Foundation

let prefix = "integral of x from 0 to infinity"
let systemPrompt = """
You are a math-to-LaTeX converter.
If the text ends with math, output exactly this format:
<original>the exact math text</original><latex>the latex conversion</latex>
IMPORTANT: <original> MUST contain the EXACT, UNMODIFIED text as it appears in the prompt. Do not change a single letter of the original text.
If there is no math, output exactly NONE.
"""

let messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": "The area of a circle is pi r squared"],
    ["role": "assistant", "content": "<original>pi r squared</original><latex>\\( \\pi r^2 \\)</latex>"],
    ["role": "user", "content": "The equation is x ^2 + y^2 = 5"],
    ["role": "assistant", "content": "<original>x ^2 + y^2 = 5</original><latex>\\( x^2 + y^2 = 5 \\)</latex>"],
    ["role": "user", "content": "Hello my name is John"],
    ["role": "assistant", "content": "NONE"],
    ["role": "user", "content": prefix]
]

let json: [String: Any] = [
    "model": "qwen2.5-coder:0.5b",
    "messages": messages,
    "stream": false,
    "options": [
        "temperature": 0.1,
        "top_p": 0.9,
        "num_predict": 64,
        "num_ctx": 1024,
        "stop": ["<|endoftext|>"]
    ]
]

let data = try! JSONSerialization.data(withJSONObject: json)
var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/chat")!)
request.httpMethod = "POST"
request.httpBody = data
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

let sema = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: request) { data, _, _ in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print("RAW SUGGESTION:")
        print(str)
        
        let rawSuggestion = str.components(separatedBy: "\"content\":\"").last!.components(separatedBy: "\"}").first!.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\").replacingOccurrences(of: "\\u003c", with: "<").replacingOccurrences(of: "\\u003e", with: ">")
        
        print("CLEANED SUGGESTION:")
        print(rawSuggestion)
        
        let pattern = "<original>(.*?)</original>\\s*<latex>(.*?)</latex>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: rawSuggestion, range: NSRange(rawSuggestion.startIndex..., in: rawSuggestion)) {
            
            let nsString = rawSuggestion as NSString
            let originalText = nsString.substring(with: match.range(at: 1))
            let latexText = nsString.substring(with: match.range(at: 2))
            
            print("MATCHED ORIGINAL: \\(originalText)")
            print("MATCHED LATEX: \\(latexText)")
            
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
                        print("SUCCESS! Replace Length: \\(matchCount)")
                        exit(0)
                    }
                    coreIndex = core.index(before: coreIndex)
                } else {
                    break
                }
            }
            print("FAILED TO MATCH PREFIX")
        } else {
            print("FAILED TO MATCH REGEX")
        }
    }
    sema.signal()
}.resume()
sema.wait()
