// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

@main
struct GlyphApp: App {
    init() {
        Bundle.swizzle()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            EditorScreen()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.automatic)
    }
}

// MARK: - Main Editor Screen

