// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import Foundation

// MARK: - Suggestion Engine

/// What the model is being asked to do.
///
/// Glyph translates the overwhelming majority of maths deterministically and instantly
/// (see `GlyphMath`). The model is only reached for the two cases a grammar cannot
/// cover: vocabulary the lexicon does not know, and slash commands that ask for a
/// transformation ("differentiate", "solve for m") rather than a transcription.
enum SuggestionKind: Sendable {
    /// Free-typed prose the local parser declined.
    case translation
    /// An explicit `/command`.
    case command
}

actor OllamaSuggestionEngine {

    private let runtime: BundledOllamaRuntime
    private let model = "qwen2.5-coder:0.5b"
    private let generateURL = URL(string: "http://127.0.0.1:11435/api/generate")!

    private var lastMessage = ""
    private var lastFailureTime: ContinuousClock.Instant?
    private let retryCooldown: Duration = .seconds(5)

    /// A dedicated session: the shared one carries cookie and cache policy that a
    /// loopback inference call has no use for.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    init(runtime: BundledOllamaRuntime) {
        self.runtime = runtime
    }

    func statusMessage() -> String { lastMessage }

    // MARK: Warmup

    func warmup() async {
        lastMessage = "Starting local AI server…"
        do {
            try await runtime.ensureRunning()
            lastMessage = "Loading AI model into memory…"

            let body = OllamaRequest(
                model: model,
                prompt: "<|fim_prefix|>// Warmup\n<|fim_suffix|><|fim_middle|>",
                raw: true,
                stream: false,
                keepAlive: "30m",
                options: .init(temperature: 0.1, topP: 0.9, numPredict: 1, numCtx: 1024, stop: ["\n"])
            )
            _ = try await send(body, timeout: 60)

            lastFailureTime = nil
            lastMessage = ""
        } catch is CancellationError {
            return
        } catch {
            lastFailureTime = .now
            lastMessage = "AI unavailable — \(error.localizedDescription)"
        }
    }

    // MARK: Suggestions

    func suggest(
        kind: SuggestionKind,
        phrase: String,
        context: String,
        replaceRange: NSRange
    ) async -> SuggestionResult? {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPhrase.isEmpty else { return nil }

        // Back off after a failure so a dead runtime does not stall every keystroke.
        if let lastFailure = lastFailureTime, ContinuousClock.now - lastFailure < retryCooldown {
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

        let prompt = Self.prompt(for: kind, phrase: trimmedPhrase, context: String(context.suffix(300)))
        let body = OllamaRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            keepAlive: "30m",
            options: .init(temperature: 0.0, topP: 0.9, numPredict: 80, numCtx: 1024, stop: ["\n"])
        )

        do {
            let response = try await send(body, timeout: kind == .command ? 8 : 12)
            let cleaned = sanitize(response.response)

            guard !cleaned.isEmpty, cleaned.uppercased() != "NONE" else {
                lastMessage = ""
                return nil
            }

            lastFailureTime = nil
            lastMessage = ""

            let latex = cleaned.hasPrefix("\\(") || cleaned.hasPrefix("\\[")
                ? cleaned
                : "\\( \(cleaned) \\)"
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

    // MARK: Transport

    private func send(_ body: OllamaRequest, timeout: TimeInterval) async throws -> OllamaResponse {
        var request = URLRequest(url: generateURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RuntimeError("Model not ready — run scripts/vendor-ollama-runtime.sh")
        }
        return try JSONDecoder().decode(OllamaResponse.self, from: data)
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Prompts

    private static func prompt(for kind: SuggestionKind, phrase: String, context: String) -> String {
        switch kind {
        case .command:   return commandPrompt(instruction: phrase, context: context)
        case .translation: return translationPrompt(phrase: phrase, context: context)
        }
    }

    private static func commandPrompt(instruction: String, context: String) -> String {
        """
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
        LaTeX: y = 3^2 = 9

        Context: The area of a circle is
        Instruction: pi r squared
        LaTeX: \\pi r^2

        Context: We compute
        Instruction: the integral of x dx
        LaTeX: \\int x \\, dx

        Context: \(context)
        Instruction: \(instruction)
        LaTeX:
        """
    }

    private static func translationPrompt(phrase: String, context: String) -> String {
        """
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
        Phrase: 4 = 
        LaTeX: 4 = x^2

        Context: The limit as delta x approaches 0 of Delta y over Delta x is 
        Phrase: limit as delta x approaches 0 of Delta y over Delta x is 
        LaTeX: \\lim_{\\delta x \\to 0} \\frac{\\Delta y}{\\Delta x}

        Context: We have y = x^2. Differentiating with respect to x gives dy/dx = 
        Phrase: dy/dx = 
        LaTeX: \\frac{dy}{dx} = 2x

        Context: The sum from n equals 1 to infinity of 1 over n squared equals pi squared over 6
        Phrase: the sum from n equals 1 to infinity of 1 over n squared equals pi squared over 6
        LaTeX: \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}

        Context: We compute the integral of sin x dx
        Phrase: the integral of sin x dx
        LaTeX: \\int \\sin x \\, dx

        Context: \(context)
        Phrase: \(phrase)
        LaTeX:
        """
    }
}

// MARK: - Bundled Ollama Runtime

actor BundledOllamaRuntime {

    private static let host = "127.0.0.1:11435"
    private static let healthURL = URL(string: "http://127.0.0.1:11435/api/tags")!

    private var process: Process?
    private var isReady = false

    func ensureRunning() async throws {
        if isReady { return }

        if await isServerResponding(timeout: 3) {
            isReady = true
            return
        }

        try startIfNeeded()

        // Poll until the API answers (up to 15 seconds).
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { throw CancellationError() }
            if await isServerResponding(timeout: 3) {
                isReady = true
                return
            }
        }
        throw RuntimeError("Local AI server did not start within 15 seconds.")
    }

    private func isServerResponding(timeout: TimeInterval) async -> Bool {
        var request = URLRequest(url: Self.healthURL)
        request.timeoutInterval = timeout
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func startIfNeeded() throws {
        guard process == nil || !(process?.isRunning ?? false) else { return }

        guard let ollamaURL = Bundle.main.url(
            forResource: "ollama",
            withExtension: nil,
            subdirectory: "Ollama"
        ) else {
            throw RuntimeError(
                "Bundled Ollama runtime not found. Run scripts/vendor-ollama-runtime.sh first."
            )
        }

        guard let modelsURL = Bundle.main.resourceURL?
            .appendingPathComponent("OllamaModels", isDirectory: true) else {
            throw RuntimeError("Bundled AI model directory is missing.")
        }

        // Reap only runners started from *this* bundle. Matching on "ollama" would
        // kill the user's own Ollama install, which they may be using for other work.
        reapOrphanedRunners(bundledExecutable: ollamaURL.path)

        // A shell wrapper so the server dies with the app even on a hard quit.
        let wrapperScript = """
        #!/bin/bash
        "\(ollamaURL.path)" serve &
        PID=$!
        while kill -0 $PPID 2>/dev/null; do
            sleep 1
        done
        kill -9 $PID
        """
        let scriptPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glyph-ollama-wrapper.sh")
        try wrapperScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath.path
        )

        let launched = Process()
        launched.executableURL = scriptPath

        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = Self.host
        environment["OLLAMA_MODELS"] = modelsURL.path
        environment["OLLAMA_KEEP_ALIVE"] = "30m"
        launched.environment = environment

        let logPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glyph-ollama.log")
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logPath) {
            launched.standardOutput = handle
            launched.standardError = handle
        }

        do {
            try launched.run()
            process = launched
        } catch {
            throw RuntimeError("Could not start bundled local AI runtime.")
        }
    }

    private func reapOrphanedRunners(bundledExecutable path: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Data Models

struct SuggestionResult: Sendable, Equatable {
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

struct OllamaResponse: Decodable {
    let response: String
}
