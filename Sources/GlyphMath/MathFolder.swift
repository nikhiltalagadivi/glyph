import Foundation

/// Turns raw lexical tokens into canonical `MathLexeme`s, folding multi-word
/// phrases ("less than or equal to", "the square root of") into single tokens.
public enum MathFolder {

    public static func fold(_ raws: [RawToken]) -> [MathLexeme] {
        var out: [MathLexeme] = []
        out.reserveCapacity(raws.count)

        var i = 0
        while i < raws.count {
            let raw = raws[i]

            switch raw.kind {
            case .number:
                out.append(MathLexeme(token: .number(raw.text), range: raw.range))
                i += 1

            case .symbol:
                out.append(MathLexeme(token: symbolToken(raw), range: raw.range))
                i += 1

            case .word:
                // `mc^2` and `3xy` are implicit products of single-letter variables.
                if let split = splitAsVariables(raws, at: i) {
                    out.append(contentsOf: split)
                    i += 1
                    continue
                }
                let (token, consumed) = wordToken(raws, at: i)
                if case .keyword(.filler) = token {
                    // "the" carries no meaning; drop it so it never anchors a span.
                    i += consumed
                    continue
                }
                let last = raws[i + consumed - 1]
                let range = NSRange(location: raw.location, length: last.end - raw.location)
                out.append(MathLexeme(token: token, range: range))
                i += consumed
            }
        }
        return out
    }

    // MARK: Implicit variable products

    /// Short unknown letter runs that sit flush against a math symbol are products of
    /// variables, not words: the `mc` of `mc^2`, the `xy` of `3xy`, the `ab` of `f(ab)`.
    ///
    /// Adjacency is the whole safeguard. A word separated by a space is left alone, so
    /// ordinary prose ("the cat sat") can never be shredded into variables.
    private static func splitAsVariables(_ raws: [RawToken], at index: Int) -> [MathLexeme]? {
        let raw = raws[index]
        guard (2...3).contains(raw.text.count),
              raw.text.allSatisfy({ $0.isASCII && $0.isLetter }),
              MathLexicon.phrases[raw.lower] == nil,
              MathLexicon.differentialVariable(for: raw.text) == nil,
              isFlushAgainstSymbol(raws, at: index) else { return nil }

        return raw.text.enumerated().map { offset, character in
            MathLexeme(
                token: .identifier(String(character)),
                range: NSRange(location: raw.location + offset, length: 1)
            )
        }
    }

    private static let followingSymbols: Set<String> = ["^", "_", "'", "!", ")", "]"]
    private static let precedingSymbols: Set<String> = ["(", "[", "^", "_"]

    private static func isFlushAgainstSymbol(_ raws: [RawToken], at index: Int) -> Bool {
        let raw = raws[index]
        if index + 1 < raws.count {
            let next = raws[index + 1]
            if next.location == raw.end, next.kind == .symbol,
               followingSymbols.contains(next.text) { return true }
        }
        if index > 0 {
            let previous = raws[index - 1]
            if previous.end == raw.location {
                if previous.kind == .number { return true }
                if previous.kind == .symbol, precedingSymbols.contains(previous.text) { return true }
            }
        }
        return false
    }

    // MARK: Words

    private static func wordToken(_ raws: [RawToken], at index: Int) -> (MathToken, Int) {
        // Longest-first phrase match over the run of consecutive word tokens.
        var runLength = 0
        while index + runLength < raws.count,
              raws[index + runLength].kind == .word,
              runLength < MathLexicon.maxPhraseWords {
            runLength += 1
        }

        if runLength > 1 {
            var joined = raws[index].lower
            var lengths: [String] = [joined]
            for k in 1..<runLength {
                joined += " " + raws[index + k].lower
                lengths.append(joined)
            }
            for count in stride(from: runLength, through: 2, by: -1) {
                if let token = MathLexicon.phrases[lengths[count - 1]] {
                    return (resolveFraction(token), count)
                }
            }
        }

        let raw = raws[index]
        if let token = MathLexicon.phrases[raw.lower] {
            return (capitalise(token, raw: raw), 1)
        }

        if let variable = MathLexicon.differentialVariable(for: raw.text) {
            return (.differential(variable), 1)
        }

        // Single letters are variables.
        if raw.text.count == 1 {
            return (.identifier(raw.text), 1)
        }

        // Short all-caps runs read as symbols ("KE", "RHS"), never as prose.
        if raw.text.count <= 3, raw.text.allSatisfy({ $0.isUppercase }) {
            return (.identifier("\\mathrm{\(raw.text)}"), 1)
        }

        return (.unknown(raw.text), 1)
    }

    /// "Delta" and "delta" are different letters; the phrase table is lowercase only.
    private static func capitalise(_ token: MathToken, raw: RawToken) -> MathToken {
        guard case .identifier(let value) = token,
              value.hasPrefix("\\"),
              let first = raw.text.first, first.isUppercase else { return token }
        let name = String(value.dropFirst())
        guard MathLexicon.capitalGreek.contains(name) else { return token }
        return .identifier("\\" + name.prefix(1).uppercased() + name.dropFirst())
    }

    /// Spoken fractions ("one half") arrive as a `1/2` number placeholder.
    private static func resolveFraction(_ token: MathToken) -> MathToken {
        guard case .number(let value) = token, value.contains("/") else { return token }
        let parts = value.split(separator: "/")
        guard parts.count == 2 else { return token }
        return .identifier("\\frac{\(parts[0])}{\(parts[1])}")
    }

    // MARK: Symbols

    private static func symbolToken(_ raw: RawToken) -> MathToken {
        if let token = MathLexicon.symbolTokens[raw.text] { return token }
        if let scalar = raw.text.unicodeScalars.first,
           raw.text.unicodeScalars.count == 1,
           let greek = MathLexicon.unicodeGreek[scalar] {
            return .identifier(greek)
        }
        return .unknown(raw.text)
    }
}
