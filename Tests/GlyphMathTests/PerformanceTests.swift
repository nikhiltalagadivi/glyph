import XCTest
import GlyphTestSupport
@testable import GlyphMath

/// The scanner runs synchronously on the main thread for every keystroke, so its
/// cost has to stay far below a frame budget even on a large document.
final class PerformanceTests: XCTestCase {

    private func report(_ label: String, _ duration: Duration) {
        let microseconds = Double(duration.components.attoseconds) / 1e12
            + Double(duration.components.seconds) * 1e6
        print(String(format: "  %-40s %8.1f µs", (label as NSString).utf8String!, microseconds))
    }

    private static let document: String = {
        let paragraph = """
        Working through the problem set today. The first result we need is the \
        relationship between energy and mass, and after that a few integrals. \
        Notes below are rough and will be tidied up later on.
        """
        return String(repeating: paragraph + "\n", count: 200)
    }()

    func testScanOnLargeDocumentIsSubMillisecond() {
        let text = Self.document + "the sum from n equals 1 to infinity of 1 over n squared"
        let iterations = 2_000

        // Warm the caches the same way typing would.
        _ = MathScopeScanner.scan(prefix: text)

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            _ = MathScopeScanner.scan(prefix: text)
        }
        let elapsed = ContinuousClock.now - start
        let perCall = elapsed / iterations

        report("scan, 40k-char document", perCall)
        XCTAssertLessThan(perCall, .milliseconds(1), "scan took \(perCall) per call")
    }

    /// The worst realistic case: a long line of prose where nothing parses, so every
    /// candidate start index is attempted and rejected.
    func testWorstCaseRejectionIsStillFast() {
        let text = String(repeating: "some ordinary words in a sentence ", count: 40)
        let iterations = 2_000

        let start = ContinuousClock.now
        for i in 0..<iterations {
            // Defeat the memo cache so this measures real parsing work.
            _ = MathScopeScanner.scan(prefix: text + String(i))
        }
        let elapsed = ContinuousClock.now - start
        report("scan, long prose line (worst case)", elapsed / iterations)
        XCTAssertLessThan(elapsed / iterations, .milliseconds(2), "rejection path too slow")
    }

    func testTypingAPhraseCharacterByCharacterStaysFast() {
        let phrase = "the integral from 0 to 1 of x squared plus 3 x minus 5 dx"
        let start = ContinuousClock.now
        for repetition in 0..<50 {
            let salt = String(repetition)
            for end in 1...phrase.count {
                _ = MathScopeScanner.scan(prefix: salt + String(phrase.prefix(end)))
            }
        }
        let elapsed = ContinuousClock.now - start
        let keystrokes = 50 * phrase.count
        report("scan, per keystroke while typing", elapsed / keystrokes)
        XCTAssertLessThan(elapsed / keystrokes, .milliseconds(1), "per-keystroke cost too high")
    }

    func testCorpusTranslationThroughput() {
        let phrases = MathCorpus.translatable
        let start = ContinuousClock.now
        for i in 0..<200 {
            for phrase in phrases { _ = MathTranslator.translate(phrase + String(i)) }
        }
        let elapsed = ContinuousClock.now - start
        report("translate, uncached corpus phrase", elapsed / (200 * phrases.count))
        XCTAssertLessThan(elapsed / (200 * phrases.count), .milliseconds(1))
    }
}
