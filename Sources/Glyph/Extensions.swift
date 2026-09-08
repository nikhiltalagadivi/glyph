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

