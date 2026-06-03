import Foundation

let systemPrompt = """
You are a math-to-LaTeX converter.
If the text ends with math, output exactly this format:
<original>the exact math text</original><latex>the latex conversion</latex>
If there is no math, output exactly NONE.
"""

let prefix = "The equation is x ^2 + y^2 = 5"

let messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": "The area of a circle is pi r squared"],
    ["role": "assistant", "content": "<original>pi r squared</original><latex>\\( \\pi r^2 \\)</latex>"],
    ["role": "user", "content": "The equation is x ^2 + y^2 = 5"],
    ["role": "assistant", "content": "<original>x ^2 + y^2 = 5</original><latex>\\( x^2 + y^2 = 5 \\)</latex>"],
    ["role": "user", "content": "Hello my name is John"],
    ["role": "assistant", "content": "NONE"],
    ["role": "user", "content": "\(prefix)"]
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
        print(str)
    }
    sema.signal()
}.resume()
sema.wait()
