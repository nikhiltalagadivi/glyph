// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

// MARK: - Suggestion Engine (FIM via Ollama)

actor OllamaSuggestionEngine {
    private let runtime: BundledOllamaRuntime
    private let endpoint = URL(string: "http://127.0.0.1:11435/api/generate")!
    private let model = "qwen2.5-coder:0.5b"
    private var lastMessage = "Starting local AI…"
    private var lastFailureTime: ContinuousClock.Instant?
    private let retryCooldown: Duration = .seconds(5)

    init(runtime: BundledOllamaRuntime) {
        self.runtime = runtime
    }

    func statusMessage() -> String { lastMessage }

    func warmup() async {
        lastMessage = "Starting local AI server…"
        do {
            try await runtime.ensureRunning()
            
            lastMessage = "Loading AI model into memory…"
            let prompt = "<|fim_prefix|>// Warmup\n<|fim_suffix|><|fim_middle|>"
            let body = OllamaRequest(
                model: model,
                prompt: prompt,
                raw: true,
                stream: false,
                keepAlive: "30m",
                options: OllamaOptions(
                    temperature: 0.1, topP: 0.9, numPredict: 1, numCtx: 1024, stop: ["\n"]
                )
            )
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30.0 // Needs extra time to load model
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            
            let _ = try await URLSession.shared.data(for: request)
            
            lastFailureTime = nil
            lastMessage = ""
        } catch is CancellationError {
            return
        } catch {
            print("AI Warmup failed: \(error)")
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
        }
    }



    func suggestSlashAI(for snapshot: EditorSnapshot) async -> SuggestionResult? {
        if let lastFailure = lastFailureTime,
           ContinuousClock.now - lastFailure < retryCooldown {
            return nil
        }

        do {
            try await runtime.ensureRunning()
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = error.localizedDescription
            return nil
        }

        let nsText = snapshot.text as NSString
        let cursor = snapshot.cursorOffset
        let prefix = nsText.substring(to: cursor)
        
        // Match the slash command range
        let pattern = "(?:\\s|^)(/[^\\n]*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: prefix.utf16.count)) else {
            return nil
        }
        
        let replaceRange = match.range(at: 1)
        let rawMathText = (prefix as NSString).substring(with: NSRange(location: replaceRange.location + 1, length: replaceRange.length - 1))
        let mathText = rawMathText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Extract context before the slash command
        let contextBeforeSlash = nsText.substring(to: replaceRange.location)
        let trimmedContext = String(contextBeforeSlash.suffix(300))

        let prompt = """
You are a mathematical assistant that translates instructions and equations into LaTeX based on the surrounding context.
Context is the text typed so far. Instruction is the command to execute.
Output ONLY the raw LaTeX expression.

Context: We have y = x^2
Instruction: differentiate y
LaTeX: \\frac{dy}{dx} = 2x

Context: We define the function \\( f(x) = x^2 + 5x \\).
Instruction: differentiate f(x)
LaTeX: f'(x) = 2x + 5

Context: Let f(x) = x^3.
Instruction: evaluate f'(2)
LaTeX: f'(2) = 12

Context: Given E = mc^2
Instruction: solve for m
LaTeX: m = \\frac{E}{c^2}

Context: Let \\( y = x^2 \\).
Instruction: substitute x = 3 to get y
LaTeX: y = 9

Context: The area of a circle is
Instruction: pi r squared
LaTeX: \\pi r^2

Context: We compute
Instruction: the integral of x dx
LaTeX: \\int x \\, dx

Context: \(trimmedContext)
Instruction: \(mathText)
LaTeX:
"""

        let body = OllamaRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            keepAlive: "30m",
            options: OllamaOptions(
                temperature: 0.0,
                topP: 0.9,
                numPredict: 80,
                numCtx: 1024,
                stop: ["\n"]
            )
        )

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/generate")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 6.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                lastFailureTime = .now
                lastMessage = "Model not ready — run scripts/vendor-ollama-runtime.sh"
                return nil
            }

            let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
            let rawSuggestion = sanitize(ollamaResponse.response)

            let cleaned = rawSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.uppercased() == "NONE" || cleaned.isEmpty {
                lastMessage = ""
                return nil
            }

            lastFailureTime = nil
            lastMessage = ""

            let latex: String
            if cleaned.hasPrefix("\\(") || cleaned.hasPrefix("\\[") {
                latex = cleaned
            } else {
                latex = "\\( \(cleaned) \\)"
            }

            return SuggestionResult(text: latex, replaceRange: replaceRange)

        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
            return nil
        }
    }

    func suggestOllama(for mathPhrase: String, context: String, replaceRange: NSRange) async -> SuggestionResult? {
        if let lastFailure = lastFailureTime,
           ContinuousClock.now - lastFailure < retryCooldown {
            return nil
        }

        do {
            try await runtime.ensureRunning()
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = error.localizedDescription
            return nil
        }
        
        let trimmedContext = String(context.suffix(300))
        let prompt = """
You are a mathematical assistant that translates and completes math equations into LaTeX based on the surrounding context.
Context is the text typed so far. Phrase is the specific part to translate/complete.
Output ONLY the raw LaTeX expression.

Context: The area of a circle is pi r squared
Phrase: pi r squared
LaTeX: \\pi r^2

Context: Let f(x) = x^3. The derivative is f'(x) = 
Phrase: f'(x) = 
LaTeX: f'(x) = 3x^2

Context: We have y = x^2. Substituting y = 4 yields 4 = 
Phrase: Substituting y = 4 yields 4 = 
LaTeX: 4 = x^2

Context: Let \\( y = x^2 \\). If we substitute x = 3, then we obtain y = 
Phrase: substitute x = 3, then we obtain y = 
LaTeX: y = 9

Context: Let delta x be a small change, then Delta y is 
Phrase: delta x be a small change, then Delta y is 
LaTeX: \\delta x \\text{ be a small change, then } \\Delta y \\text{ is}

Context: The limit as delta x approaches 0 of Delta y over Delta x is 
Phrase: limit as delta x approaches 0 of Delta y over Delta x is 
LaTeX: \\lim_{\\delta x \\to 0} \\frac{\\Delta y}{\\Delta x}

Context: We have y = x^2. Differentiating with respect to x gives dy/dx = 
Phrase: Differentiating with respect to x gives dy/dx = 
LaTeX: \\frac{dy}{dx} = 2x

Context: We define the function \\( f(x) = x^2 + 5x \\). Differentiating it gives f'(x) = 
Phrase: Differentiating it gives f'(x) = 
LaTeX: f'(x) = 2x + 5

Context: The sum from n equals 1 to infinity of 1 over n squared equals pi squared over 6
Phrase: the sum from n equals 1 to infinity of 1 over n squared equals pi squared over 6
LaTeX: \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}

Context: We compute the integral of sin x dx
Phrase: the integral of sin x dx
LaTeX: \\int \\sin x \\, dx

Context: \(trimmedContext)
Phrase: \(mathPhrase)
LaTeX:
"""

        let body = OllamaRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            keepAlive: "30m",
            options: OllamaOptions(
                temperature: 0.0,
                topP: 0.9,
                numPredict: 80,
                numCtx: 1024,
                stop: ["\n"]
            )
        )

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/generate")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                lastFailureTime = .now
                lastMessage = "Model not ready — run scripts/vendor-ollama-runtime.sh"
                return nil
            }

            let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
            let rawSuggestion = sanitize(ollamaResponse.response)

            let cleaned = rawSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.uppercased() == "NONE" || cleaned.isEmpty {
                lastMessage = ""
                return nil
            }

            lastFailureTime = nil
            lastMessage = ""

            let latex: String
            if cleaned.hasPrefix("\\(") || cleaned.hasPrefix("\\[") {
                latex = cleaned
            } else {
                latex = "\\( \(cleaned) \\)"
            }

            return SuggestionResult(text: latex, replaceRange: replaceRange)

        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
            return nil
        }
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bundled Ollama Runtime

actor BundledOllamaRuntime {
    private var process: Process?
    private var isReady = false

    func ensureRunning() async throws {
        if isReady { return }
        
        let healthURL = URL(string: "http://127.0.0.1:11435/api/tags")!
        
        // Fast-path: check if it's already running (either by us, or an orphaned process)
        var fastReq = URLRequest(url: healthURL)
        fastReq.timeoutInterval = 3.0
        if let (_, response) = try? await URLSession.shared.data(for: fastReq),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            isReady = true
            return
        }

        isReady = false

        // Start the process if it's not running
        if process == nil || !(process?.isRunning ?? false) {
            // Force kill any existing zombie ollama runners to avoid CPU saturation and free GPU
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-f", "ollama"]
            try? killTask.run()
            killTask.waitUntilExit()

            guard let ollamaURL = Bundle.main.url(
                forResource: "ollama",
                withExtension: nil,
                subdirectory: "Ollama"
            ) else {
                throw RuntimeError(
                    "Bundled Ollama runtime not found. "
                    + "Run scripts/vendor-ollama-runtime.sh first."
                )
            }

            guard let modelsURL = Bundle.main.resourceURL?
                .appendingPathComponent("OllamaModels", isDirectory: true) else {
                throw RuntimeError("Bundled AI model directory is missing.")
            }

            let wrapperScript = """
            #!/bin/bash
            "\(ollamaURL.path)" serve &
            PID=$!
            while kill -0 $PPID 2>/dev/null; do
                sleep 1
            done
            kill -9 $PID
            """
            let scriptPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ollama-wrapper.sh")
            try? wrapperScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            let launched = Process()
            launched.executableURL = scriptPath
            launched.arguments = []
            
            var env = ProcessInfo.processInfo.environment
            env["OLLAMA_HOST"] = "127.0.0.1:11435"
            env["OLLAMA_MODELS"] = modelsURL.path
            env["OLLAMA_KEEP_ALIVE"] = "30m"
            launched.environment = env

            let logPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tabnote-ollama.log")
            FileManager.default.createFile(atPath: logPath.path, contents: nil, attributes: nil)
            if let fh = try? FileHandle(forWritingTo: logPath) {
                launched.standardOutput = fh
                launched.standardError = fh
            }

            do {
                try launched.run()
                process = launched
            } catch {
                throw RuntimeError("Could not start bundled local AI runtime.")
            }
        }

        // Poll until the API is responsive (up to 15 seconds)
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { throw CancellationError() }
            do {
                var healthReq = URLRequest(url: healthURL)
                healthReq.timeoutInterval = 3.0
                let (_, response) = try await URLSession.shared.data(for: healthReq)
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    isReady = true
                    return
                }
            } catch {
                continue
            }
        }

        throw RuntimeError("Local AI server did not start within 15 seconds.")
    }
}

// MARK: - Data Models

struct EditorSnapshot: Sendable {
    let text: String
    let cursorOffset: Int
}

struct SuggestionResult: Sendable {
    let text: String
    let replaceRange: NSRange?
}

struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let raw: Bool
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, prompt, raw, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct OllamaOptions: Encodable {
    let temperature: Double
    let topP: Double
    let numPredict: Int
    let numCtx: Int
    let stop: [String]

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
        case numCtx = "num_ctx"
        case stop
    }
}

struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let raw: Bool
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, prompt, raw, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatResponse: Decodable {
    let message: ChatMessage
}

struct OllamaResponse: Decodable {
    let response: String
}

