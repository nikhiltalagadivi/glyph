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
    ["role": "user", "content": "The area of a circle is pi r squared"],
    ["role": "assistant", "content": "<original>pi r squared</original><latex>\\( \\pi r^2 \\)</latex>"],
    ["role": "user", "content": "The equation is x ^2 + y^2 = 5"],
    ["role": "assistant", "content": "<original>x ^2 + y^2 = 5</original><latex>\\( x^2 + y^2 = 5 \\)</latex>"],
    ["role": "user", "content": "calculate the integral of x from 0 to infinity"],
    ["role": "assistant", "content": "<original>integral of x from 0 to infinity</original><latex>\\( \\int_{0}^{\\infty} x \\, dx \\)</latex>"],
    ["role": "user", "content": "the quadratic formula is x = -b plus or minus square root of b squared minus 4ac over 2a"],
    ["role": "assistant", "content": "<original>x = -b plus or minus square root of b squared minus 4ac over 2a</original><latex>\\( x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a} \\)</latex>"],
    ["role": "user", "content": "the sum of x squared from 0 to 5"],
    ["role": "assistant", "content": "<original>the sum of x squared from 0 to 5</original><latex>\\( \\sum_{x=0}^{5} x^2 \\)</latex>"],
    ["role": "user", "content": "matrix A with rows 1 2 and 3 4 times vector x y equals vector 5 6"],
    ["role": "assistant", "content": "<original>matrix A with rows 1 2 and 3 4 times vector x y equals vector 5 6</original><latex>\\( \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix} \\begin{pmatrix} x \\\\ y \\end{pmatrix} = \\begin{pmatrix} 5 \\\\ 6 \\end{pmatrix} \\)</latex>"],
    ["role": "user", "content": "Hello my name is John"],
    ["role": "assistant", "content": "NONE"],
    ["role": "user", "content": "and the work w is the integral from t1 to t2 of force f dot velocity v dt."]
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
