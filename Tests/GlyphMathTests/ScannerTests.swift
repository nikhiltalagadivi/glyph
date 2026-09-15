import XCTest
@testable import GlyphMath

final class ScannerTests: XCTestCase {

    /// Convenience: the substring the scanner selected, so range bugs are visible.
    private func selection(_ text: String) -> (String, String)? {
        guard let result = MathScopeScanner.scan(prefix: text) else { return nil }
        return ((text as NSString).substring(with: result.range), result.latex)
    }

    func testPicksTheMathTailOutOfASentence() {
        let (span, latex) = try! XCTUnwrap(selection("The area of a circle is pi r squared"))
        XCTAssertEqual(span, "pi r squared")
        XCTAssertEqual(latex, "\\pi r^2")
    }

    func testPrefersTheLongestParseableSpan() {
        let (span, latex) = try! XCTUnwrap(
            selection("We know that x squared plus y squared equals z squared")
        )
        XCTAssertEqual(span, "x squared plus y squared equals z squared")
        XCTAssertEqual(latex, "x^2 + y^2 = z^2")
    }

    func testStopsAtSentencePunctuation() {
        let (span, _) = try! XCTUnwrap(selection("That was x. Now pi r squared"))
        XCTAssertEqual(span, "pi r squared")
    }

    func testNeverCrossesARenderedEquation() {
        // U+FFFC is the attachment character standing in for an existing equation.
        let text = "we had \u{FFFC} plus the integral of x dx"
        let (span, _) = try! XCTUnwrap(selection(text))
        XCTAssertEqual(span, "the integral of x dx")
    }

    func testOnlyScansTheCurrentLine() {
        let text = "first line with x squared\nthe square root of 2"
        let (span, latex) = try! XCTUnwrap(selection(text))
        XCTAssertEqual(span, "the square root of 2")
        XCTAssertEqual(latex, "\\sqrt{2}")
    }

    func testRangesAreUTF16CorrectAfterNonBMPCharacters() {
        let text = "🎓🎓 pi r squared"
        let result = try! XCTUnwrap(MathScopeScanner.scan(prefix: text))
        XCTAssertEqual((text as NSString).substring(with: result.range), "pi r squared")
    }

    func testProseProducesNothing() {
        for text in ["Hello world", "Just some ordinary writing here", "A note about the meeting"] {
            XCTAssertNil(MathScopeScanner.scan(prefix: text), "fired on: \(text)")
        }
    }

    func testEmptyAndWhitespaceInput() {
        XCTAssertNil(MathScopeScanner.scan(prefix: ""))
        XCTAssertNil(MathScopeScanner.scan(prefix: "   "))
        XCTAssertNil(MathScopeScanner.scan(prefix: "\n\n"))
    }

    func testTrailingWhitespaceIsNotPartOfTheReplacement() {
        let result = try! XCTUnwrap(MathScopeScanner.scan(prefix: "value is pi r squared   "))
        XCTAssertEqual((result.range.location + result.range.length), 21)
    }

    func testVeryLongLineStaysBounded() {
        let filler = String(repeating: "word ", count: 5_000)
        let text = filler + "pi r squared"
        let result = try! XCTUnwrap(MathScopeScanner.scan(prefix: text))
        XCTAssertEqual((text as NSString).substring(with: result.range), "pi r squared")
    }

    // MARK: Model fallback

    func testLooksMathyOnlyForUnhandledMathPhrases() {
        XCTAssertTrue(MathScopeScanner.looksMathy(prefix: "the integral of the gaussian"))
        XCTAssertTrue(MathScopeScanner.looksMathy(prefix: "differentiate the polynomial"))
        XCTAssertFalse(MathScopeScanner.looksMathy(prefix: "we went to the shops"))
        XCTAssertFalse(MathScopeScanner.looksMathy(prefix: "a perfectly ordinary sentence"))
    }

    func testLlmRangeStaysOnTheCurrentSentence() {
        let text = "Some notes. now integrate the gaussian"
        let range = try! XCTUnwrap(MathScopeScanner.llmRange(prefix: text))
        XCTAssertEqual((text as NSString).substring(with: range), "now integrate the gaussian")
    }

    func testScannerNeverCrashesOnAdversarialInput() {
        let inputs = [
            String(repeating: "(", count: 5_000),
            String(repeating: "x^", count: 2_000),
            String(repeating: "\u{FFFC}", count: 500),
            "\u{0000}\u{0001}\u{FEFF}",
            String(repeating: "the integral of ", count: 300)
        ]
        for input in inputs { _ = MathScopeScanner.scan(prefix: input) }
    }
}
