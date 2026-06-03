// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

struct FormattingToolbar: View {
    let viewModel: EditorViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            FormatButton(icon: "bold", isActive: viewModel.isBold) {
                viewModel.toggleBold()
            }
            FormatButton(icon: "italic", isActive: viewModel.isItalic) {
                viewModel.toggleItalic()
            }
            FormatButton(icon: "underline", isActive: viewModel.isUnderlined) {
                viewModel.toggleUnderline()
            }
            FormatButton(icon: "strikethrough", isActive: viewModel.isStrikethrough) {
                viewModel.toggleStrikethrough()
            }
            
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)
            
            FormatButton(icon: "arrow.up.doc", isActive: false) {
                viewModel.exportAsMarkdown()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
    }
}

private struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let message: String
    let isHighlighted: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
    }
}


