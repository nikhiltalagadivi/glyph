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
    } else {
        // Already in \(...\) or \[...\] form — pass through
        processed = markdown
    }

    let images = LaTeX.renderToImages(processed, displayScale: NSScreen.main?.backingScaleFactor ?? 2.0)
    
    guard let img = images.first else {
        print("createMathImage: renderToImages returned empty array for '\(processed)'")
        return nil
    }
    
    // Scale up the image slightly to match the 20pt size
    img.isTemplate = true
    return img
}

