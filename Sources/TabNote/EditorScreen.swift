// ============================================================
// TabNote — Freewriting with AI Tab Completion
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
                // Glass formatting toolbar
                FormattingToolbar(viewModel: viewModel)
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

