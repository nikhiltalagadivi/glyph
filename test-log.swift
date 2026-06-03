import Foundation
let p = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tabnote-ollama.log").path
if let content = try? String(contentsOfFile: p) {
    print(content)
}
