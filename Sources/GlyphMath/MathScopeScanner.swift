import Foundation

public struct MathScanResult: Sendable, Equatable {
    /// Range within the text that was scanned, ready to hand to `NSTextStorage`.
    public let range: NSRange
    public let latex: String
    public let score: Int

    public var inlineDelimited: String { "\\( \(latex) \\)" }
}

/// Locates the maximal math expression ending at the caret.
///
/// The grammar itself decides what counts as math: the scanner offers progressively
/// shorter suffixes of the current line and keeps the longest one the parser accepts.
/// That removes the guesswork of keyword heuristics — anything with a word the lexicon
/// does not know simply fails to parse.
public enum MathScopeScanner {

    /// Never look further back than this many tokens, so a very long line stays cheap.
    private static let maximumTokens = 32
    /// Never scan more than this many UTF-16 units of the current line.
    private static let maximumLineLength = 600

    /// `text` is the document prefix up to the caret.
    public static func scan(prefix text: String) -> MathScanResult? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let (line, lineOffset) = currentLine(of: nsText)
        guard !line.isEmpty else { return nil }

        let lexemes = MathFolder.fold(MathTokenizer.tokenize(line))
        guard !lexemes.isEmpty else { return nil }

        // Any unknown token is an impassable wall: no candidate may span it.
        var lowerBound = 0
        for (i, lexeme) in lexemes.enumerated() {
            if case .unknown = lexeme.token { lowerBound = i + 1 }
        }
        lowerBound = max(lowerBound, lexemes.count - maximumTokens)
        guard lowerBound < lexemes.count else { return nil }

        let nsLine = line as NSString

        // Ascending start index means longest candidate first.
        for start in lowerBound..<lexemes.count {
            // "…plus the integral of x dx" — a spelled-out operator at the head of the
            // span is prose glue, not a unary sign. The symbolic "-x + 1" is fine.
            if case .additive = lexemes[start].token, startsWithLetter(nsLine, lexemes[start].range) {
                continue
            }
            let slice = lexemes[start...]
            guard let translation = MathTranslator.translate(lexemes: slice) else { continue }
            let first = lexemes[start].range
            let last = lexemes[lexemes.count - 1].range
            let range = NSRange(
                location: lineOffset + first.location,
                length: (last.location + last.length) - first.location
            )
            return MathScanResult(range: range, latex: translation.latex, score: translation.score)
        }
        return nil
    }

    /// Whether the tail still looks mathematical enough to be worth a model call
    /// after `scan` has declined it.
    public static func looksMathy(prefix text: String) -> Bool {
        llmRange(prefix: text) != nil
    }

    /// The span a language model should be asked to rewrite, when the deterministic
    /// parser cannot handle the phrase.
    public static func llmRange(prefix text: String) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let (line, lineOffset) = currentLine(of: nsText)
        let raws = MathTokenizer.tokenize(line)
        guard !raws.isEmpty else { return nil }

        // Walk back to the last sentence boundary or rendered equation.
        var start = 0
        for (i, raw) in raws.enumerated() where isHardBoundary(raw) {
            start = i + 1
        }
        start = max(start, raws.count - maximumTokens)
        guard start < raws.count else { return nil }

        let tail = raws[start...]
        let hasHint = tail.contains { raw in
            switch raw.kind {
            case .word: return MathLexicon.strongHints.contains(raw.lower)
            case .symbol: return ["=", "+", "^", "/", "*", "-"].contains(raw.text)
            case .number: return false
            }
        }
        guard hasHint, tail.count >= 2 else { return nil }

        // Trim leading tokens that cannot begin an expression.
        var first = start
        while first < raws.count, !canOpenPhrase(raws[first]) { first += 1 }
        guard first < raws.count, raws.count - first >= 2 else { return nil }

        let head = raws[first]
        let last = raws[raws.count - 1]
        return NSRange(location: lineOffset + head.location, length: last.end - head.location)
    }

    // MARK: Helpers

    /// Returns the text of the line containing the caret and its offset in `text`.
    private static func currentLine(of nsText: NSString) -> (String, Int) {
        let searchStart = max(0, nsText.length - maximumLineLength)
        let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
        let newline = nsText.rangeOfCharacter(from: .newlines, options: .backwards, range: searchRange)

        var offset = newline.location == NSNotFound ? searchStart : NSMaxRange(newline)
        // When the window was clipped mid-word, advance to the next whitespace so a
        // partial word never masquerades as a token.
        if newline.location == NSNotFound, searchStart > 0 {
            let space = nsText.rangeOfCharacter(
                from: .whitespaces,
                options: [],
                range: NSRange(location: offset, length: nsText.length - offset)
            )
            if space.location != NSNotFound { offset = NSMaxRange(space) }
        }
        guard offset < nsText.length else { return ("", offset) }
        return (nsText.substring(from: offset), offset)
    }

    private static func startsWithLetter(_ line: NSString, _ range: NSRange) -> Bool {
        guard range.length > 0, range.location < line.length else { return false }
        let scalar = Unicode.Scalar(line.character(at: range.location))
        return scalar.map { CharacterSet.letters.contains($0) } ?? false
    }

    private static func isHardBoundary(_ raw: RawToken) -> Bool {
        guard raw.kind == .symbol else { return false }
        return [".", "?", "!", ";", ":", "\"", "\u{FFFC}", "\\", "$", "\u{201C}", "\u{201D}"]
            .contains(raw.text)
    }

    private static func canOpenPhrase(_ raw: RawToken) -> Bool {
        switch raw.kind {
        case .number: return true
        case .word: return !["is", "are", "the", "a", "an", "of", "to", "and", "or",
                             "equals", "gives", "yields", "then", "so", "thus"].contains(raw.lower)
        case .symbol: return ["(", "[", "{", "-", "\u{221A}", "\u{222B}", "\u{2211}"].contains(raw.text)
        }
    }
}
