import Foundation

let systemPrompt = """
You are a math-to-LaTeX converter.
If the text ends with math, output exactly this format:
<original>the exact math text</original><latex>the latex conversion</latex>
IMPORTANT: <original> MUST be a case-insensitive, exact, unmodified substring from the very end of the user's text! Do not change a single letter.
If there is no math at the very end, or it's just normal conversation, output NONE.
Only convert the math part, not the conversational text before it.
"""

let messages = [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": "The kinetic energy ke is 1/2mv^2 "],
]

let payload: [String: Any] = [
    "model": "qwen2.5-coder:0.5b",
    "messages": messages,
    "temperature": 0.0,
    "stream": false
]

let jsonData = try! JSONSerialization.data(withJSONObject: payload)
var req = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/chat")!)
req.httpMethod = "POST"
req.httpBody = jsonData

let sema = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: req) { data, _, _ in
    if let data = data, let str = String(data: data, encoding: .utf8) {
        print(str)
    }
    sema.signal()
}.resume()
sema.wait()
