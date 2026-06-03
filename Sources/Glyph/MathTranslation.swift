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
        .unencoded()
        .font(.system(size: 20))
        .foregroundColor(.black)
        .renderingStyle(.wait)
        .fixedSize()

    let hostingController = NSHostingController(rootView: view)
    let viewSize = hostingController.sizeThatFits(in: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    
    guard viewSize.width > 0 && viewSize.height > 0 else {
        return nil
    }
    
    hostingController.view.setFrameSize(viewSize)
    hostingController.view.layout()
    
    guard let rep = hostingController.view.bitmapImageRepForCachingDisplay(in: hostingController.view.bounds) else {
        return nil
    }
    hostingController.view.cacheDisplay(in: hostingController.view.bounds, to: rep)
    
    let img = NSImage(size: viewSize)
    img.addRepresentation(rep)
    img.isTemplate = true
    
    print("createMathImage via NSHostingController for: '\(markdown)' -> img: \(img)")
    return img
}

