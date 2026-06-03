// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

struct EditorScreen: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        ZStack(alignment: .center) {
            // Full-bleed rich text editor
            RichTextEditor(viewModel: viewModel)
                .ignoresSafeArea()

            // Floating UI overlays
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Menu {
                        Button(action: { viewModel.toggleBold() }) { Label("Bold", systemImage: "bold") }
                        Button(action: { viewModel.toggleItalic() }) { Label("Italic", systemImage: "italic") }
                        Button(action: { viewModel.toggleUnderline() }) { Label("Underline", systemImage: "underline") }
                        Button(action: { viewModel.toggleStrikethrough() }) { Label("Strikethrough", systemImage: "strikethrough") }
                        Divider()
                        Button(action: { viewModel.exportAsMarkdown() }) { Label("Export as Markdown", systemImage: "arrow.up.doc") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.top, 12)

                Spacer()

                // Glass status pill
                if !viewModel.statusMessage.isEmpty && viewModel.statusMessage != "thinking…" && viewModel.statusMessage != "⇥ Tab" {
                    StatusPill(
                        message: viewModel.statusMessage,
                        isHighlighted: viewModel.currentSuggestion != nil
                    )
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, 16)
            .animation(.smooth(duration: 0.25), value: viewModel.statusMessage.isEmpty || viewModel.statusMessage == "thinking…" || viewModel.statusMessage == "⇥ Tab")
        }
        .task {
            await viewModel.startupAI()
        }
    }
}

// MARK: - Formatting Toolbar

