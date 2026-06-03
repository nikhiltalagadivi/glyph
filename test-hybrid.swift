import Foundation

let systemPrompt = """
You are an inline text assistant.
CRITICAL RULES:
1. NEVER converse. NEVER say "Sure" or "Here is".
2. If the text ends with math, output EXACTLY this format: <original>the exact math text</original><latex>the latex conversion</latex>
3. If there is NO math, just output the NEXT 1-5 WORDS to seamlessly continue the sentence.
"""

let messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt],
    ["role": "user", "content": "The area of a circle is pi r squared"],
    ["role": "assistant", "content": "<original>pi r squared</original><latex>\\( \\pi r^2 \\)</latex>"],
    ["role": "user", "content": "The equation is x ^2 + y^2 = 5"],
    ["role": "assistant", "content": "<original>x ^2 + y^2 = 5</original><latex>\\( x^2 + y^2 = 5 \\)</latex>"],
    ["role": "user", "content": "Hello my name is"],
    ["role": "assistant", "content": " John and I am"],
    ["role": "user", "content": "I am going to the store to buy some"]
]

let json: [String: Any] = [
    "model": "qwen2.5-coder:0.5b",
    "messages": messages,
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
