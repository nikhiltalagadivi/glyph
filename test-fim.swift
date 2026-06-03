import Foundation

let json: [String: Any] = [
    "model": "qwen2.5-coder:0.5b",
    "prompt": "<|fim_prefix|>Here is a math problem: x ^2 + y^2 = 5<|fim_suffix|><|fim_middle|>",
    "raw": true,
    "stream": false,
    "options": [
        "temperature": 0.1,
        "top_p": 0.9,
        "num_predict": 16,
        "stop": ["<|file_separator|>", "<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<|endoftext|>"]
    ]
]

let data = try! JSONSerialization.data(withJSONObject: json)
var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/generate")!)
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
