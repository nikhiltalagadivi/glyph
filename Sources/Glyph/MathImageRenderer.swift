// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftMath

// MARK: - Math Image Renderer (SwiftMath — native Core Graphics)

/// How an equation is set.
///
/// TeX makes this distinction and so should we: an equation inside a sentence should
/// stay on the line, while one that stands alone gets room to breathe with limits
/// above and below their operators.
enum MathRenderStyle {
    /// Inside a sentence — compact, limits beside the operator.
    case inline
    /// Alone on its line — full height, limits above and below.
    case display

    var fontSize: CGFloat {
        switch self {
        case .inline: return 20
        case .display: return 23
        }
    }
}

private enum MathImageConstants {
    /// Baked at 3× so printed output and Retina display both stay crisp.
    static let bakeScale: CGFloat = 3.0
    static let cacheLimit = 400
}

/// Rendering an equation costs roughly a millisecond and allocates a bitmap several
/// hundred kilobytes wide. Opening a note re-renders every equation in it, and the
/// print path renders them all a second time in black — so the results are cached.
@MainActor
private final class MathImageCache {
    static let shared = MathImageCache()

    private let storage: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = MathImageConstants.cacheLimit
        return cache
    }()

    func image(for key: String) -> NSImage? { storage.object(forKey: key as NSString) }

    func store(_ image: NSImage, for key: String) { storage.setObject(image, forKey: key as NSString) }

    /// Appearance changes invalidate every colour-dependent bitmap.
    func removeAll() { storage.removeAllObjects() }
}

/// Drops cached bitmaps when the system switches between light and dark.
@MainActor
func invalidateMathImageCache() {
    MathImageCache.shared.removeAll()
}

@MainActor
func createMathImage(
    for markdown: String,
    color: NSColor? = nil,
    style: MathRenderStyle = .inline
) -> NSImage? {
    let rawLatex = stripLatexDelimiters(markdown)
    guard !rawLatex.isEmpty else { return nil }

    // Resolve the dynamic text colour up front: AppKit's template rendering mishandles
    // dynamic colours inside baked bitmaps.
    let textColor: NSColor
    if let color {
        textColor = color
    } else {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        textColor = isDark ? .white : .black
    }

    let cacheKey = "\(textColor.hashValue)|\(style)|\(rawLatex)"
    if let cached = MathImageCache.shared.image(for: cacheKey) { return cached }

    let mathImage = MTMathImage(
        latex: rawLatex,
        fontSize: style.fontSize,
        textColor: textColor,
        labelMode: style == .display ? .display : .text,
        textAlignment: .left
    )

    let (error, image) = mathImage.asImage()
    guard error == nil, let image else { return nil }

    let baked = bakeNSImage(image)
    MathImageCache.shared.store(baked, for: cacheKey)
    return baked
}

/// Bakes a vector-drawing-backed `NSImage` into a static high-resolution bitmap.
///
/// Without this, AppKit's print engine re-evaluates the drawing handler inside a
/// flipped graphics context and renders the equation upside down.
private func bakeNSImage(_ image: NSImage) -> NSImage {
    let targetSize = image.size
    guard targetSize.width > 0, targetSize.height > 0 else { return image }

    let scale = MathImageConstants.bakeScale
    let pixelSize = NSSize(width: targetSize.width * scale, height: targetSize.height * scale)

    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize.width.rounded(.up)),
        pixelsHigh: Int(pixelSize.height.rounded(.up)),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return image
    }

    bitmapRep.size = targetSize

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    image.draw(in: NSRect(origin: .zero, size: targetSize))
    NSGraphicsContext.restoreGraphicsState()

    let baked = NSImage(size: targetSize)
    baked.addRepresentation(bitmapRep)
    return baked
}

/// Strips `\( … \)`, `\[ … \]`, `$ … $` and `$$ … $$` delimiters.
func stripLatexDelimiters(_ input: String) -> String {
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)

    if s.hasPrefix("$$"), s.hasSuffix("$$"), s.count > 4 {
        s = String(s.dropFirst(2).dropLast(2))
    } else if s.hasPrefix("\\["), s.hasSuffix("\\]"), s.count > 4 {
        s = String(s.dropFirst(2).dropLast(2))
    } else if s.hasPrefix("\\("), s.hasSuffix("\\)"), s.count > 4 {
        s = String(s.dropFirst(2).dropLast(2))
    } else if s.hasPrefix("$"), s.hasSuffix("$"), s.count > 2 {
        s = String(s.dropFirst().dropLast())
    }

    return s.trimmingCharacters(in: .whitespaces)
}

// MARK: - Attachment construction

/// Builds the attachment run that replaces a phrase in the text storage: the rendered
/// equation, its LaTeX source (so it survives save/load and export), and a trailing
/// space so the caret lands somewhere sensible.
@MainActor
func mathAttachmentString(
    image: NSImage,
    source: String,
    font: NSFont,
    includeTrailingSpace: Bool = true
) -> NSMutableAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.labelColor
    ]
    let attachment = NSTextAttachment()
    attachment.image = image
    attachment.bounds = mathAttachmentBounds(imageSize: image.size, font: font)

    let result = NSMutableAttributedString(attachment: attachment)
    result.addAttributes(attributes, range: NSRange(location: 0, length: result.length))
    result.addAttribute(.latexSource, value: source, range: NSRange(location: 0, length: result.length))
    if includeTrailingSpace {
        result.append(NSAttributedString(string: " ", attributes: attributes))
    }
    return result
}

/// Centres the equation image on the text baseline for the given font.
func mathAttachmentBounds(imageSize: NSSize, font: NSFont) -> CGRect {
    let lineHeight = font.ascender - font.descender
    let yOffset = font.descender - (imageSize.height - lineHeight) / 2
    return CGRect(origin: CGPoint(x: 0, y: yOffset), size: imageSize)
}

/// Whether the equation occupying `range` stands alone on its line.
///
/// A paragraph holding nothing but the equation (and whitespace) is set in display
/// style; anything else keeps it inline so the sentence stays on one line.
@MainActor
func mathStyle(for range: NSRange, in storage: NSTextStorage) -> MathRenderStyle {
    let text = storage.string as NSString
    guard range.location < text.length else { return .inline }

    // Scanned in place: this runs for every equation on every keystroke, so it must
    // not copy the paragraph.
    let paragraph = text.paragraphRange(for: range)
    let whitespace = CharacterSet.whitespacesAndNewlines
    for index in paragraph.location..<NSMaxRange(paragraph) {
        let unit = text.character(at: index)
        if unit == 0xFFFC { continue }
        guard let scalar = Unicode.Scalar(unit), whitespace.contains(scalar) else {
            return .inline
        }
    }
    return .display
}
