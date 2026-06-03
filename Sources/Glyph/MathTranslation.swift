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

    // Render at 20pt to match the visual weight of the surrounding 18pt system font
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(.black)
        .fixedSize()

    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let img = renderer.nsImage
    img?.isTemplate = true
    print("createMathImage for: '\(markdown)' -> img: \(String(describing: img))")
    return img
}

