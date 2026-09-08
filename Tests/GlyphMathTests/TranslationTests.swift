import XCTest
import GlyphTestSupport
@testable import GlyphMath

final class TranslationTests: XCTestCase {

    func testCorpusTranslatesExactly() {
        var failures: [String] = []
        for (phrase, expected) in MathCorpus.expectations {
            guard let translation = MathTranslator.translate(phrase) else {
                failures.append("\(phrase)\n    expected: \(expected)\n    got:      <rejected>")
                continue
            }
            if translation.latex != expected {
                failures.append("\(phrase)\n    expected: \(expected)\n    got:      \(translation.latex)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "\n" + failures.joined(separator: "\n"))
    }

    func testProseIsNeverTranslated() {
        var failures: [String] = []
        for phrase in MathCorpus.rejections {
            if let translation = MathTranslator.translate(phrase) {
                failures.append("\(phrase) → \(translation.latex)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "False positives:\n" + failures.joined(separator: "\n"))
    }

    // MARK: Structural guarantees

    func testUnknownWordRejectsTheWholePhrase() {
        XCTAssertNil(MathTranslator.translate("x squared plus quux"))
        XCTAssertNil(MathTranslator.translate("the integral of gaussian dx"))
    }

    func testLoneSymbolsAreNotWorthRendering() {
        for phrase in ["x", "5", "pi", "alpha", "n", "3.14"] {
            XCTAssertNil(MathTranslator.translate(phrase), "should reject \(phrase)")
        }
    }

    func testPartialWordsDoNotFire() {
        // Typing "squ…" toward "squared" must not produce a suggestion mid-word.
        XCTAssertNil(MathTranslator.translate("x squ"))
        XCTAssertNil(MathTranslator.translate("pi r squa"))
        XCTAssertNotNil(MathTranslator.translate("pi r squared"))
    }

    func testWordsThatContainOperatorsAreNotOperators() {
        // "since" starts with "sin", "overall" starts with "over".
        XCTAssertNil(MathTranslator.translate("x since y"))
        XCTAssertNil(MathTranslator.translate("2 overall 3"))
        XCTAssertNil(MathTranslator.translate("the pie is good"))
    }

    func testCapitalGreekIsDistinctFromLowercase() {
        XCTAssertEqual(MathTranslator.translate("Delta x plus delta y")?.latex,
                       "\\Delta x + \\delta y")
    }

    func testImplicitVariableProductsOnlyWhenFlushAgainstSymbols() {
        XCTAssertEqual(MathTranslator.translate("E = mc^2")?.latex, "E = mc^2")
        // A spaced word is prose, never a product of variables.
        XCTAssertNil(MathTranslator.translate("E = mc squared and cat sat"))
    }

    func testWordOperatorsBindLooselyAndSymbolsBindTightly() {
        // Spoken division takes the whole product; a slash takes one factor.
        XCTAssertEqual(MathTranslator.translate("Delta y over Delta x")?.latex,
                       "\\frac{\\Delta y}{\\Delta x}")
        XCTAssertEqual(MathTranslator.translate("4/3 pi r^3")?.latex,
                       "\\frac{4}{3}\\pi r^3")
        // Same for exponentiation.
        XCTAssertEqual(MathTranslator.translate("e to the power of i pi")?.latex, "e^{i \\pi}")
        XCTAssertEqual(MathTranslator.translate("e^i pi")?.latex, "e^i \\pi")
    }

    func testChainedRelationsAndNestedStructures() {
        XCTAssertEqual(MathTranslator.translate("0 < x < 1")?.latex, "0 < x < 1")
        XCTAssertEqual(MathTranslator.translate("sqrt(sqrt(x))")?.latex, "\\sqrt{\\sqrt{x}}")
        XCTAssertEqual(MathTranslator.translate("1/(1/x)")?.latex, "\\frac{1}{\\frac{1}{x}}")
    }

    func testStackedExponentsStayValidLatex() {
        // `x^2^3` is not legal TeX; the base must be braced.
        XCTAssertEqual(MathTranslator.translate("x^2^3")?.latex, "{x^2}^3")
    }

    func testRedundantBracketsAreDropped() {
        XCTAssertEqual(MathTranslator.translate("sqrt(x + 1)")?.latex, "\\sqrt{x + 1}")
        XCTAssertEqual(MathTranslator.translate("(a + b)/(c + d)")?.latex,
                       "\\frac{a + b}{c + d}")
    }

    func testTranslationIsDeterministicAndCached() {
        let first = MathTranslator.translate("the integral from 0 to 1 of x squared dx")
        let second = MathTranslator.translate("the integral from 0 to 1 of x squared dx")
        XCTAssertEqual(first, second)
    }

    // MARK: Robustness

    func testMalformedInputNeverCrashes() {
        let inputs = [
            "((((", "))))", "^^^^", "___", "\\\\\\", "$$$", "|||", "((x", "x))",
            "1/", "/1", "+", "-", "= =", "sqrt(", "the integral of", "sum from",
            "lim as", "the derivative of with respect to", "x^", "x_", "^2",
            "0.0.0.0", "..", "e^{", "}{", "\u{FFFC}\u{FFFC}", "\u{0000}",
            String(repeating: "x + ", count: 400),
            String(repeating: "(", count: 200) + "x" + String(repeating: ")", count: 200)
        ]
        for input in inputs {
            _ = MathTranslator.translate(input)   // must simply not trap
        }
    }

    func testDeeplyNestedInputTerminates() {
        let nested = String(repeating: "sqrt(", count: 60) + "x" + String(repeating: ")", count: 60)
        _ = MathTranslator.translate(nested)
    }
}
