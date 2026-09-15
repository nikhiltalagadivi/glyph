// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI

/// Every measurement and colour the editor uses, in one place.
///
/// The look is deliberately plain: one system accent, no tinted chrome, and a single
/// serif for body text that sits alongside the TeX the equations are set in.
enum EditorTheme {

    // MARK: Type

    static let bodySize: CGFloat = 18
    static let titleSize: CGFloat = 26

    /// New York. It shares the proportions of Computer Modern, so an equation dropped
    /// mid-sentence reads as part of the same typeface rather than a pasted graphic.
    static var body: NSFont { serif(size: bodySize, weight: .regular) }
    static var title: NSFont { serif(size: titleSize, weight: .bold) }

    private static func serif(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: Rhythm

    /// Generous leading: an equation is far taller than a line of text, and without
    /// air around it the paragraph reads as a collision rather than a sentence.
    static let lineSpacing: CGFloat = 7
    static let paragraphSpacing: CGFloat = 9
    static let titleParagraphSpacing: CGFloat = 18

    /// Longest comfortable line. Beyond roughly this width the eye loses the return
    /// sweep, so the column is centred instead of filling the window.
    static let maximumMeasure: CGFloat = 700
    static let minimumSideInset: CGFloat = 32
    static let topInset: CGFloat = 64

    static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        return style
    }

    static var titleParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = titleParagraphSpacing
        return style
    }

    // MARK: Attribute sets

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: body,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle
        ]
    }

    static var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: title,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleParagraphStyle
        ]
    }

    // MARK: Sidebar

    enum Sidebar {
        static let rowCornerRadius: CGFloat = 7
        static let rowPaddingH: CGFloat = 10
        static let rowPaddingV: CGFloat = 7
        static let width: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (200, 236, 300)
    }

    // MARK: Colour

    /// The one accent, taken from the user's system setting rather than invented.
    static var accent: NSColor { .controlAccentColor }
}
