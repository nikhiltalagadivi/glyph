import Foundation

// MARK: - Raw lexical token

/// A single lexical unit of the source text, with a UTF-16 range so ranges can be
/// handed straight to `NSTextStorage` without re-scanning the string.
public struct RawToken: Sendable, Equatable {
    public enum Kind: Sendable { case word, number, symbol }

    public let kind: Kind
    public let text: String
    /// `text` lowercased once at tokenization time; every lexicon lookup uses it.
    public let lower: String
    public let location: Int
    public let length: Int

    public var end: Int { location + length }
    public var range: NSRange { NSRange(location: location, length: length) }

    init(kind: Kind, text: String, location: Int, length: Int) {
        self.kind = kind
        self.text = text
        self.lower = kind == .word ? text.lowercased() : text
        self.location = location
        self.length = length
    }
}

// MARK: - Tokenizer

public enum MathTokenizer {

    /// The object-replacement character AppKit uses for text attachments. An already
    /// rendered equation is a hard boundary: never scan across one.
    public static let attachmentMarker: Character = "\u{FFFC}"

    /// Multi-character ASCII operators, matched longest-first.
    private static let digraphs: [[UInt8]] = [
        Array("<=>".utf8), Array("<->".utf8), Array("...".utf8),
        Array(":=".utf8), Array("<=".utf8), Array(">=".utf8),
        Array("!=".utf8), Array("~=".utf8), Array("==".utf8),
        Array("->".utf8), Array("=>".utf8), Array("+-".utf8),
        Array("-+".utf8), Array("**".utf8)
    ]

    /// Splits `text` into words, numbers and symbols. Whitespace is dropped; the
    /// original offsets survive in each token's range.
    ///
    /// Runs in a single pass over the unicode scalars with no regex and no
    /// intermediate allocations beyond the token strings themselves.
    public static func tokenize(_ text: String) -> [RawToken] {
        var tokens: [RawToken] = []
        tokens.reserveCapacity(text.utf16.count / 3 + 4)

        let scalars = Array(text.unicodeScalars)
        // UTF-16 offset of each scalar index, so token ranges line up with NSString.
        var offsets = [Int](repeating: 0, count: scalars.count + 1)
        var utf16Offset = 0
        for (i, s) in scalars.enumerated() {
            offsets[i] = utf16Offset
            utf16Offset += UTF16.width(s)
        }
        offsets[scalars.count] = utf16Offset

        var i = 0
        while i < scalars.count {
            let s = scalars[i]

            if isSpace(s) { i += 1; continue }

            if isASCIILetter(s) {
                let start = i
                while i < scalars.count, isASCIILetter(scalars[i]) { i += 1 }
                append(&tokens, .word, scalars, start, i, offsets)
                continue
            }

            if isDigit(s) {
                let start = i
                while i < scalars.count, isDigit(scalars[i]) { i += 1 }
                // A decimal point only continues the number if a digit follows it.
                if i + 1 < scalars.count, scalars[i] == ".", isDigit(scalars[i + 1]) {
                    i += 1
                    while i < scalars.count, isDigit(scalars[i]) { i += 1 }
                }
                append(&tokens, .number, scalars, start, i, offsets)
                continue
            }

            // A leading ".5" is a number; a bare "." is sentence punctuation.
            if s == ".", i + 1 < scalars.count, isDigit(scalars[i + 1]) {
                let start = i
                i += 1
                while i < scalars.count, isDigit(scalars[i]) { i += 1 }
                append(&tokens, .number, scalars, start, i, offsets)
                continue
            }

            if s.isASCII, let width = matchDigraph(scalars, at: i) {
                append(&tokens, .symbol, scalars, i, i + width, offsets)
                i += width
                continue
            }

            append(&tokens, .symbol, scalars, i, i + 1, offsets)
            i += 1
        }

        return tokens
    }

    private static func append(
        _ tokens: inout [RawToken],
        _ kind: RawToken.Kind,
        _ scalars: [Unicode.Scalar],
        _ start: Int,
        _ endExclusive: Int,
        _ offsets: [Int]
    ) {
        var view = String.UnicodeScalarView()
        view.reserveCapacity(endExclusive - start)
        for k in start..<endExclusive { view.append(scalars[k]) }
        let loc = offsets[start]
        tokens.append(RawToken(kind: kind, text: String(view), location: loc, length: offsets[endExclusive] - loc))
    }

    private static func matchDigraph(_ scalars: [Unicode.Scalar], at index: Int) -> Int? {
        for pattern in digraphs {
            guard index + pattern.count <= scalars.count else { continue }
            var matched = true
            for (k, byte) in pattern.enumerated() where scalars[index + k].value != UInt32(byte) {
                matched = false
                break
            }
            if matched { return pattern.count }
        }
        return nil
    }

    @inline(__always)
    private static func isSpace(_ s: Unicode.Scalar) -> Bool {
        s == " " || s == "\t" || s == "\n" || s == "\r" || s == "\u{00A0}" || s == "\u{2009}"
    }

    @inline(__always)
    private static func isASCIILetter(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122)
    }

    @inline(__always)
    private static func isDigit(_ s: Unicode.Scalar) -> Bool {
        s.value >= 48 && s.value <= 57
    }
}
