// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// MARK: - Math Image Renderer

@MainActor
func createMathImage(for markdown: String) -> NSImage? {
    // Normalise delimiter styles to \(...\) / \[...\]
    let processed: String
    if markdown.hasPrefix("$$"), markdown.hasSuffix("$$") {
        processed = "\\[" + markdown.dropFirst(2).dropLast(2) + "\\]"
    } else if markdown.hasPrefix("$"), markdown.hasSuffix("$") {
        processed = "\\(" + markdown.dropFirst().dropLast() + "\\)"
    } else if !markdown.contains("\\(") && !markdown.contains("\\[") && !markdown.contains("$") {
        // Raw LaTeX without delimiters — wrap it
        processed = "\\( " + markdown + " \\)"
    } else {
        // Already in \(...\) or \[...\] form — pass through
        processed = markdown
    }

    // Try rendering with LaTeXSwiftUI
    // Use a hosting view approach which is more reliable than ImageRenderer for complex LaTeX
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    
    // Approach 1: NSHostingView-based bitmap (more reliable than ImageRenderer)
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(.black)
        .fixedSize()

    let hostingView = NSHostingView(rootView: view)
    hostingView.frame.size = hostingView.fittingSize
    
    // Give it a moment to layout — complex LaTeX needs this
    hostingView.layoutSubtreeIfNeeded()
    
    let size = hostingView.fittingSize
    guard size.width > 0, size.height > 0 else {
        print("createMathImage: fittingSize is zero for '\(markdown)'")
        // Fallback to ImageRenderer
        return createMathImageFallback(processed: processed, scale: scale)
    }
    
    hostingView.frame = NSRect(origin: .zero, size: size)
    
    guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        print("createMathImage: bitmapRep is nil for '\(markdown)'")
        return createMathImageFallback(processed: processed, scale: scale)
    }
    
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
    
    let image = NSImage(size: size)
    image.addRepresentation(bitmapRep)
    image.isTemplate = true
    
    // Verify the image isn't blank (all transparent)
    if isImageBlank(bitmapRep) {
        print("createMathImage: bitmap is blank for '\(markdown)', trying fallback")
        return createMathImageFallback(processed: processed, scale: scale)
    }
    
    print("createMathImage for: '\(markdown)' -> img: \(image.size)")
    return image
}

@MainActor
private func createMathImageFallback(processed: String, scale: CGFloat) -> NSImage? {
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(.black)
        .fixedSize()

    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    
    guard let img = renderer.nsImage else {
        print("createMathImage fallback: ImageRenderer also returned nil")
        return nil
    }
    
    img.isTemplate = true
    print("createMathImage fallback succeeded: \(img.size)")
    return img
}

private func isImageBlank(_ rep: NSBitmapImageRep) -> Bool {
    guard let data = rep.bitmapData else { return true }
    let bytesPerRow = rep.bytesPerRow
    let height = rep.pixelsHigh
    let width = rep.pixelsWide
    let samplesPerPixel = rep.samplesPerPixel
    
    // Check if there's any non-zero alpha pixel
    guard samplesPerPixel >= 4 else { return false } // Can't check alpha, assume not blank
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * samplesPerPixel
            let alpha = data[offset + 3]
            if alpha > 10 { return false } // Found a non-transparent pixel
        }
    }
    return true
}
