// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

extension NSAttributedString.Key {
    static let latexSource = NSAttributedString.Key("com.tabnote.latexSource")
}

struct RuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

@MainActor
func createTabKeyImage(font: NSFont) -> NSImage {
    let text = "⇥ Tab"
    let buttonFont = NSFont.systemFont(ofSize: font.pointSize * 0.70, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: buttonFont,
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    let size = text.size(withAttributes: attributes)
    let padding = CGSize(width: 8, height: 3)
    let rect = CGRect(origin: .zero, size: CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2))
    
    let image = NSImage(size: rect.size)
    image.lockFocus()
    
    let isDark = NSApp.effectiveAppearance.name == .darkAqua || NSApp.effectiveAppearance.name == .vibrantDark
    
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
    NSColor.labelColor.withAlphaComponent(isDark ? 0.2 : 0.06).setFill()
    path.fill()
    NSColor.labelColor.withAlphaComponent(isDark ? 0.3 : 0.12).setStroke()
    path.lineWidth = 1.0
    path.stroke()
    
    text.draw(at: CGPoint(x: padding.width, y: padding.height), withAttributes: attributes)
    
    image.unlockFocus()
    return image
}

// MARK: - Bundle Swizzler for SPM Resources in App Bundles
extension Bundle {
    private static let swizzleInitWithPath: Void = {
        let orgSelector = NSSelectorFromString("initWithPath:")
        let altSelector = #selector(Bundle.customInit(path:))
        
        guard let originalMethod = class_getInstanceMethod(Bundle.self, orgSelector),
              let alternateMethod = class_getInstanceMethod(Bundle.self, altSelector) else {
            return
        }
        
        method_exchangeImplementations(originalMethod, alternateMethod)
    }()
    
    @objc private func customInit(path: String) -> Bundle? {
        var finalPath = path
        if path.hasSuffix("SwiftMath_SwiftMath.bundle") {
            if let resourceURL = Bundle.main.resourceURL {
                let redirectURL = resourceURL.appendingPathComponent("SwiftMath_SwiftMath.bundle")
                if FileManager.default.fileExists(atPath: redirectURL.path) {
                    finalPath = redirectURL.path
                }
            }
        }
        return self.customInit(path: finalPath)
    }
    
    static func swizzle() {
        _ = swizzleInitWithPath
    }
}

