import XCTest
import SwiftMath
import GlyphTestSupport
@testable import GlyphMath

/// Every phrase the translator accepts must produce LaTeX that SwiftMath can build.
/// If it cannot, the app silently shows nothing — so this is treated as a hard failure.
final class RenderValidityTests: XCTestCase {

    func testAllTranslationsRender() throws {
        var failures: [String] = []
        for phrase in MathCorpus.translatable {
            guard let translation = MathTranslator.translate(phrase) else {
                failures.append("NOT TRANSLATED: \(phrase)")
                continue
            }
            var error: NSError?
            let list = MTMathListBuilder.build(fromString: translation.latex, error: &error)
            if let error {
                failures.append("\(phrase)\n    latex: \(translation.latex)\n    error: \(error.localizedDescription)")
            } else if list == nil {
                failures.append("\(phrase)\n    latex: \(translation.latex)\n    error: nil math list")
            }
        }
        XCTAssertTrue(failures.isEmpty, "LaTeX that SwiftMath cannot render:\n" + failures.joined(separator: "\n"))
    }

    /// Negative control: proves the renderer really does reject bad markup, so a
    /// green result above means something.
    func testRendererRejectsUnsupportedCommands() {
        for bad in ["\\notarealcommand{x}", "\\left( x", "\\begin{nope} x \\end{nope}"] {
            var error: NSError?
            _ = MTMathListBuilder.build(fromString: bad, error: &error)
            XCTAssertNotNil(error, "expected \(bad) to fail")
        }
    }

    /// Guards the individual commands the translator can emit, including ones no
    /// corpus phrase happens to reach.
    func testEmittedCommandsAreSupported() throws {
        let snippets = [
            "\\pi r^2", "\\frac{dy}{dx}", "\\frac{\\partial f}{\\partial x}",
            "\\sqrt{2}", "\\sqrt[3]{27}", "\\int_0^1 x^2 \\, dx",
            "\\int\\!\\!\\int f \\, dx", "\\oint F \\, ds",
            "\\sum_{n = 1}^{\\infty} \\frac{1}{n^2}", "\\prod_{k = 1}^n k",
            "\\lim_{x \\to 0} \\frac{\\sin x}{x}", "\\limsup_{n \\to \\infty} a_n",
            "\\left| x - 3 \\right| < 5", "\\left\\| v \\right\\|",
            "\\binom{n}{k}", "x \\;\\mathrm{mod}\\; 3", "\\mathrm{KE} = \\frac{1}{2}mv^2",
            "x \\in \\mathbb{R}", "A \\subseteq B", "A \\cup B", "A \\cap B",
            "\\forall x \\exists y", "f^{\\prime}(x)", "f^{\\prime\\prime}(x)",
            "A^{-1}", "A^T", "z^*", "5\\%", "90^{\\circ}", "x \\to 0^-",
            "a \\pm b", "a \\mp b", "\\nabla \\times F", "\\alpha \\beta \\gamma",
            "\\Delta y", "x \\leq 5", "y \\neq 0", "x \\approx y", "a \\equiv b",
            "a \\propto b", "P(A \\mid B)", "\\ldots", "\\emptyset",
            "\\setminus", "a \\parallel b", "a \\perp b", "\\log_2 x",
            "\\sin^2 \\theta + \\cos^2 \\theta = 1", "\\mathrm{sech} x",
            "x \\Rightarrow y", "x \\iff y", "\\aleph", "\\hbar", "\\ell",
            "{x^2}^3", "\\left( \\frac{a}{b} \\right)"
        ]
        var failures: [String] = []
        for snippet in snippets {
            var error: NSError?
            let list = MTMathListBuilder.build(fromString: snippet, error: &error)
            if let error {
                failures.append("\(snippet) → \(error.localizedDescription)")
            } else if list == nil {
                failures.append("\(snippet) → nil math list")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Unsupported LaTeX:\n" + failures.joined(separator: "\n"))
    }
}
