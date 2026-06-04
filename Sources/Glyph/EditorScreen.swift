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
    @AppStorage("hasShownWelcome") private var hasShownWelcome = false
    @State private var showWelcome = false
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
            
            if showWelcome {
                ZStack {
                    Color.black
                        .opacity(0.4)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    VStack(spacing: 24) {
                        if let appIcon = NSImage(named: "NSApplicationIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        } else {
                            Image(systemName: "pencil.and.outline")
                                .font(.system(size: 64))
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(spacing: 8) {
                            Text("Welcome to Glyph")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            Text("A minimalist writing environment powered by local intelligence.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        VStack(alignment: .leading, spacing: 18) {
                            FeatureRow(
                                icon: "keyboard",
                                title: "Freewrite & Complete",
                                description: "Write naturally. The local AI engine silently predicts the continuation of your thoughts. Press Tab ⇥ to accept suggestions instantly."
                            )
                            
                            FeatureRow(
                                icon: "terminal",
                                title: "Intentional AI Prompts",
                                description: "Start any sentence or line with a slash (/) to command the AI. Use it to formulate LaTeX equations, render mathematics, or translate descriptions."
                            )
                        }
                        .padding(.horizontal, 8)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                showWelcome = false
                                hasShownWelcome = true
                            }
                        }) {
                            Text("Start Writing")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(32)
                    .frame(width: 440)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 12)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
        .task {
            if !hasShownWelcome {
                showWelcome = true
            }
            await viewModel.startupAI()
        }
    }
}

// MARK: - Welcome View Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Formatting Toolbar

