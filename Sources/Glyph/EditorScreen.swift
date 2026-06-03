// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

struct EditorScreen: View {
    @State private var viewModel = EditorViewModel()
    @State private var isMenuExpanded = false

    var body: some View {
        ZStack(alignment: .center) {
            // Full-bleed rich text editor
            RichTextEditor(viewModel: viewModel)
                .ignoresSafeArea()

            // Floating UI overlays
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if isMenuExpanded {
                            Button(action: { viewModel.toggleBold() }) {
                                Image(systemName: "bold")
                                    .font(.system(size: 14, weight: viewModel.isBold ? .bold : .medium))
                                    .foregroundStyle(viewModel.isBold ? .primary : .secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.toggleItalic() }) {
                                Image(systemName: "italic")
                                    .font(.system(size: 14, weight: viewModel.isItalic ? .bold : .medium))
                                    .foregroundStyle(viewModel.isItalic ? .primary : .secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.toggleUnderline() }) {
                                Image(systemName: "underline")
                                    .font(.system(size: 14, weight: viewModel.isUnderlined ? .bold : .medium))
                                    .foregroundStyle(viewModel.isUnderlined ? .primary : .secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { viewModel.toggleStrikethrough() }) {
                                Image(systemName: "strikethrough")
                                    .font(.system(size: 14, weight: viewModel.isStrikethrough ? .bold : .medium))
                                    .foregroundStyle(viewModel.isStrikethrough ? .primary : .secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 18)
                                .padding(.horizontal, 4)
                            
                            Button(action: { viewModel.exportAsMarkdown() }) {
                                Image(systemName: "arrow.up.doc")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 18)
                                .padding(.horizontal, 4)
                        }
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isMenuExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isMenuExpanded ? "xmark" : "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(isMenuExpanded ? .horizontal : .all, isMenuExpanded ? 14 : 0)
                    .padding(isMenuExpanded ? .vertical : .all, isMenuExpanded ? 6 : 0)
                    .frame(height: 36)
                    .frame(width: isMenuExpanded ? nil : 36)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
                }
                .padding(.top, 16)

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
            .ignoresSafeArea(.container, edges: .top)
            .animation(.smooth(duration: 0.25), value: viewModel.statusMessage.isEmpty || viewModel.statusMessage == "thinking…" || viewModel.statusMessage == "⇥ Tab")
        }
        .task {
            await viewModel.startupAI()
        }
    }
}

// MARK: - Formatting Toolbar

