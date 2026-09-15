import XCTest
import AppKit
import SwiftMath

/// Measures what stripping equation bitmaps before archiving actually saves.
/// Enabled with GLYPH_BENCH=1; it reports numbers rather than asserting on them.
final class SavePayloadBenchmark: XCTestCase {

    func testArchiveSizeWithAndWithoutBakedImages() throws {
        guard ProcessInfo.processInfo.environment["GLYPH_BENCH"] != nil else { return }

        let latexSource = NSAttributedString.Key("com.tabnote.latexSource")
        let equations = [
            "\\pi r^2",
            "\\sum_{n = 1}^{\\infty} \\frac{1}{n^2}",
            "\\lim_{x \\to 0} \\frac{\\sin x}{x}",
            "E = mc^2"
        ]

        let document = NSMutableAttributedString(
            string: "Some notes about the problem set, roughly a paragraph of prose.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 18)]
        )

        for latex in equations {
            let mathImage = MTMathImage(latex: latex, fontSize: 20, textColor: .black,
                                        labelMode: .display, textAlignment: .left)
            let (_, image) = mathImage.asImage()
            let baked = try XCTUnwrap(image)

            let attachment = NSTextAttachment()
            attachment.image = baked
            let run = NSMutableAttributedString(attachment: attachment)
            run.addAttribute(latexSource, value: latex, range: NSRange(location: 0, length: run.length))
            document.append(run)
            document.append(NSAttributedString(string: " and then more prose here.\n"))
        }

        let withImages = try NSKeyedArchiver.archivedData(
            withRootObject: document, requiringSecureCoding: false
        )

        let stripped = NSMutableAttributedString(attributedString: document)
        stripped.enumerateAttribute(
            latexSource, in: NSRange(location: 0, length: stripped.length), options: []
        ) { value, range, _ in
            guard value is String else { return }
            stripped.removeAttribute(.attachment, range: range)
        }
        let withoutImages = try NSKeyedArchiver.archivedData(
            withRootObject: stripped, requiringSecureCoding: false
        )

        func time(_ block: () throws -> Void) rethrows -> Duration {
            let start = ContinuousClock.now
            for _ in 0..<20 { try block() }
            return (ContinuousClock.now - start) / 20
        }

        let withTime = try time {
            _ = try NSKeyedArchiver.archivedData(withRootObject: document, requiringSecureCoding: false)
        }
        let withoutTime = try time {
            let copy = NSMutableAttributedString(attributedString: document)
            copy.enumerateAttribute(
                latexSource, in: NSRange(location: 0, length: copy.length), options: []
            ) { value, range, _ in
                guard value is String else { return }
                copy.removeAttribute(.attachment, range: range)
            }
            _ = try NSKeyedArchiver.archivedData(withRootObject: copy, requiringSecureCoding: false)
        }

        print("""

        === Save payload, 4 equations + prose ===
        with baked images : \(withImages.count) bytes, \(withTime) per archive
        images stripped   : \(withoutImages.count) bytes, \(withoutTime) per archive
        reduction         : \(String(format: "%.1f", Double(withImages.count) / Double(withoutImages.count)))x smaller
        """)
    }
}
