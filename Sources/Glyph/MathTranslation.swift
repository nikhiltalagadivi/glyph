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
    
    // Use SwiftMath's MTMathImage for direct Core Graphics rendering
    let mathImage = MTMathImage(
        latex: rawLatex,
        fontSize: 20,
        textColor: .labelColor,
        labelMode: .display,
        textAlignment: .left
    )
    
    let (error, image) = mathImage.asImage()
    
    if let error = error {
        print("createMathImage error for '\(rawLatex)': \(error.localizedDescription)")
        return nil
    }
    
    guard let img = image else {
        print("createMathImage: nil image for '\(rawLatex)'")
        return nil
    }
    
    print("createMathImage for: '\(rawLatex)' -> size: \(img.size)")
    return img
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
