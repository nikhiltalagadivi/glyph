import Foundation

public struct MathTranslation: Sendable, Equatable {
    /// LaTeX without delimiters, e.g. `\pi r^{2}`.
    public let latex: String
    /// How much mathematical structure the phrase carried.
    public let score: Int

    public init(latex: String, score: Int) {
        self.latex = latex
        self.score = score
    }

    /// Wrapped in the inline delimiters the editor stores on attachments.
    public var inlineDelimited: String { "\\( \(latex) \\)" }
}

/// Deterministic natural-language / shorthand → LaTeX translation.
///
/// This is the fast path: it runs synchronously on every keystroke in well under a
/// millisecond and never touches the network. The language model is only consulted
/// for phrases this refuses.
public enum MathTranslator {

    /// Below this, a phrase carries too little structure to be worth rendering —
    /// a lone variable or bare number stays plain text.
    public static let minimumScore = 2

    public static func translate(_ phrase: String) -> MathTranslation? {
        let key = phrase
        if let cached = cache.value(for: key) { return cached.value }
        let result = uncachedTranslate(phrase)
        cache.store(result, for: key)
        return result
    }

    private static func uncachedTranslate(_ phrase: String) -> MathTranslation? {
        let lexemes = MathFolder.fold(MathTokenizer.tokenize(phrase))
        return translate(lexemes: lexemes)
    }

    /// Translates an already-folded token run. Used by the scanner, which folds once
    /// and then tries several starting points.
    public static func translate(lexemes: some Collection<MathLexeme>) -> MathTranslation? {
        let list = Array(lexemes)
        guard !list.isEmpty else { return nil }
        guard let (node, score) = try? MathParser.parse(list) else { return nil }
        guard score >= minimumScore else { return nil }
        let latex = node.latex
        guard !latex.isEmpty else { return nil }
        return MathTranslation(latex: latex, score: score)
    }

    // MARK: Cache

    private static let cache = TranslationCache()
}

/// A bounded memo for translations. Keystroke-by-keystroke typing re-tests the same
/// prefixes constantly, so even a small cache removes most repeated parsing.
private final class TranslationCache: @unchecked Sendable {
    struct Box { let value: MathTranslation? }

    private let lock = NSLock()
    private var storage: [String: Box] = [:]
    private let limit = 1024

    func value(for key: String) -> Box? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func store(_ value: MathTranslation?, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        // Whole-cache eviction: cheaper than LRU bookkeeping and the working set is tiny.
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[key] = Box(value: value)
    }
}
