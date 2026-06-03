// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

struct LatexEditPopoverView: View {
    @State private var latexText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(initialLatex: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _latexText = State(initialValue: initialLatex)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit LaTeX Equation")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
            
            TextEditor(text: $latexText)
                .font(.system(.body, design: .monospaced))
                .frame(width: 320, height: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") {
                    onSave(latexText)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 344)
    }
}

// MARK: - Local Math Translation Heuristic

