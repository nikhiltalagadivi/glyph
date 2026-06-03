// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftMath

// MARK: - Math Image Renderer (SwiftMath — native Core Graphics)

@MainActor
func createMathImage(for markdown: String) -> NSImage? {
    // Strip LaTeX delimiters to get raw math content
    let rawLatex = stripDelimiters(markdown)
    guard !rawLatex.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    
    // Use SwiftMath's MTMathUILabel to render natively via Core Graphics
    let label = MTMathUILabel()
    label.latex = rawLatex
    label.fontSize = 20
    label.textColor = .labelColor
    label.textAlignment = .left
    label.labelMode = .text
    
    // Force layout to compute intrinsic size
    let intrinsicSize = label.intrinsicContentSize
    guard intrinsicSize.width > 0, intrinsicSize.height > 0 else {
        print("createMathImage: intrinsicContentSize is zero for '\(rawLatex)'")
        return nil
    }
    
    // Add a small amount of padding
    let padding: CGFloat = 2
    let renderSize = NSSize(
        width: intrinsicSize.width + padding * 2,
        height: intrinsicSize.height + padding * 2
    )
    
    label.frame = NSRect(origin: NSPoint(x: padding, y: padding), size: intrinsicSize)
    
    // Render to a high-DPI NSImage
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let pixelSize = NSSize(width: renderSize.width * scale, height: renderSize.height * scale)
    
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize.width),
        pixelsHigh: Int(pixelSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("createMathImage: failed to create bitmap rep")
        return nil
    }
    
    // Draw into the bitmap at high resolution
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context
    
    let cgContext = context.cgContext
    cgContext.scaleBy(x: scale, y: scale)
    
    // Clear background (transparent)
    cgContext.clear(CGRect(origin: .zero, size: renderSize))
    
    // Draw the math label
    label.draw(CGRect(origin: .zero, size: renderSize))
    
    NSGraphicsContext.restoreGraphicsState()
    
    // Build the final NSImage at logical size
    let image = NSImage(size: renderSize)
    image.addRepresentation(bitmapRep)
    image.isTemplate = true
    
    print("createMathImage for: '\(rawLatex)' -> size: \(renderSize)")
    return image
}

/// Strips `\( ... \)`, `\[ ... \]`, `$ ... $`, `$$ ... $$` delimiters from LaTeX
private func stripDelimiters(_ input: String) -> String {
    var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // $$ ... $$
    if s.hasPrefix("$$") && s.hasSuffix("$$") && s.count > 4 {
        s = String(s.dropFirst(2).dropLast(2))
    }
    // \[ ... \]
    else if s.hasPrefix("\\[") && s.hasSuffix("\\]") {
        s = String(s.dropFirst(2).dropLast(2))
    }
    // \( ... \)
    else if s.hasPrefix("\\(") && s.hasSuffix("\\)") {
        s = String(s.dropFirst(2).dropLast(2))
    }
    // $ ... $
    else if s.hasPrefix("$") && s.hasSuffix("$") && s.count > 2 {
        s = String(s.dropFirst().dropLast())
    }
    
    return s.trimmingCharacters(in: .whitespaces)
}
