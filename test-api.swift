import Foundation

let systemPrompt = """
You are an inline text-completion assistant. 
CRITICAL RULES:
1. If the user's text ends with plain English math, output JSON: {"action": "replace", "length": N, "latex": "LaTeX"}
2. Otherwise, just output JSON: {"action": "continue", "text": "next few words"}
"""

let messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": "Text:\nThe area of a circle is pi r squared"],
    ["role": "assistant", "content": "{\"action\": \"replace\", \"length\": 12, \"latex\": \"\\\\( \\\\pi r^2 \\\\)\"}"],
    ["role": "user", "content": "Text:\nx ^2 + y^2 = 5"],
    ["role": "assistant", "content": "{\"action\": \"replace\", \"length\": 14, \"latex\": \"\\\\( x^2 + y^2 = 5 \\\\)\"}"],
    ["role": "user", "content": "Text:\nwe know that z = a / b"]
]

let json: [String: Any] = [
    "model": "qwen2.5-coder:0.5b",
    "messages": messages,
    "format": "json",
    "stream": false,
    "options": [
        "temperature": 0.1,
        "top_p": 0.9,
        "num_predict": 64
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
        print(str)
    }
    sema.signal()
}.resume()
sema.wait()
