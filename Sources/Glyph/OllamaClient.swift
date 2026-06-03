// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
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
        
        guard !mathText.isEmpty else { return nil }

        let prompt = """
Translate math to LaTeX. ONLY raw LaTeX.
Input: pi r squared
Output: \\pi r^2
Input: integral from 0 to infinity of x dx
Output: \\int_{0}^{\\infty} x \\, dx
Input: \(mathText)
Output:
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
                numPredict: 40,
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

    func suggestOllama(for mathPhrase: String, replaceRange: NSRange) async -> SuggestionResult? {
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
        
        let prompt = """
Translate math to LaTeX. ONLY raw LaTeX.
Input: pi r squared
Output: \\pi r^2
Input: integral from 0 to infinity of x dx
Output: \\int_{0}^{\\infty} x \\, dx
Input: \(mathPhrase)
Output:
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
                numPredict: 60,
                numCtx: 512,
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
        var clean = text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if clean.hasPrefix("```latex") {
            clean.removeFirst("```latex".count)
        } else if clean.hasPrefix("```") {
            clean.removeFirst("```".count)
        }
        
        if clean.hasSuffix("```") {
            clean.removeLast("```".count)
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
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

