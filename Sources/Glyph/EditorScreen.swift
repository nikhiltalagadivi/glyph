// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI

// MARK: - Main Editor Screen

struct EditorScreen: View {
    @State private var viewModel = EditorViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel, isSearchFocused: $isSearchFocused)
                .navigationSplitViewColumnWidth(
                    min: EditorTheme.Sidebar.width.min,
                    ideal: EditorTheme.Sidebar.width.ideal,
                    max: EditorTheme.Sidebar.width.max
                )
        } detail: {
            EditorPane(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .background(shortcuts)
        .task { await viewModel.startupAI() }
    }

    /// Keyboard shortcuts with no visible control of their own.
    private var shortcuts: some View {
        Group {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("") {
                if let selected = viewModel.selectedNote { viewModel.deleteNote(selected) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(viewModel.selectedNote == nil)
        }
        .opacity(0)
    }
}

// MARK: - Editor Pane

private struct EditorPane: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            RichTextEditor(viewModel: viewModel)
                .ignoresSafeArea()

            if viewModel.showsStatus {
                StatusPill(message: viewModel.statusMessage)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.showsStatus)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                DocumentMenu(viewModel: viewModel)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.createNewNote) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New note (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// Everything that is not writing, folded behind one control.
private struct DocumentMenu: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isNaming = false
    @State private var draftName = ""

    var body: some View {
        Menu {
            Section("Course") {
                ForEach(viewModel.courses, id: \.self) { course in
                    Button {
                        viewModel.assignSelectedNote(to: course)
                    } label: {
                        if course == viewModel.selectedNote?.course {
                            Label(course, systemImage: "checkmark")
                        } else {
                            Text(course)
                        }
                    }
                }
                Button("New Course…") { draftName = ""; isNaming = true }
                if viewModel.selectedNote?.course != nil {
                    Button("Remove from Course") { viewModel.assignSelectedNote(to: nil) }
                }
            }
            Section("Format") {
                Button("Bold", action: viewModel.toggleBold).keyboardShortcut("b")
                Button("Italic", action: viewModel.toggleItalic).keyboardShortcut("i")
                Button("Underline", action: viewModel.toggleUnderline).keyboardShortcut("u")
                Button("Strikethrough", action: viewModel.toggleStrikethrough)
            }
            Section("Export") {
                Button("Markdown…", action: viewModel.exportAsMarkdown)
                Button("LaTeX…", action: viewModel.exportAsLaTeX)
                Button("PDF…", action: viewModel.exportAsPDF)
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help("Course, formatting and export")
        .alert("New Course", isPresented: $isNaming) {
            TextField("MATH 51", text: $draftName)
            Button("Cancel", role: .cancel) { }
            Button("Create") { viewModel.assignSelectedNote(to: draftName) }
        } message: {
            Text("Notes are grouped by course in the sidebar.")
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Bindable var viewModel: EditorViewModel
    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $viewModel.searchQuery, isFocused: $isSearchFocused)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                    ForEach(viewModel.groupedNotes) { section in
                        VStack(alignment: .leading, spacing: 1) {
                            SectionHeader(title: section.id)
                            ForEach(section.notes) { note in
                                NoteRow(
                                    note: note,
                                    isSelected: viewModel.selectedNote?.id == note.id,
                                    courses: viewModel.courses,
                                    onSelect: { viewModel.select(note) },
                                    onMove: { viewModel.setCourse($0, for: note) },
                                    onDelete: { viewModel.deleteNote(note) },
                                    onRestore: { viewModel.restoreNote(note) },
                                    onPurge: { viewModel.permanentlyDelete(note) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)

            if !viewModel.searchQuery.isEmpty {
                ResultCount(count: viewModel.filteredNotes.count)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search notes and equations", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .kerning(0.6)
            .padding(.horizontal, EditorTheme.Sidebar.rowPaddingH)
            .padding(.bottom, 5)
    }
}

private struct ResultCount: View {
    let count: Int

    var body: some View {
        Text(count == 1 ? "1 note" : "\(count) notes")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
    }
}

private struct NoteRow: View {
    let note: GlyphNote
    let isSelected: Bool
    let courses: [String]
    let onSelect: () -> Void
    let onMove: (String?) -> Void
    let onDelete: () -> Void
    let onRestore: () -> Void
    let onPurge: () -> Void

    @State private var isHovered = false

    private var timestamp: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(note.lastModified) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(note.lastModified) {
            return "Yesterday"
        } else if let week = calendar.date(byAdding: .day, value: -7, to: Date()),
                  note.lastModified > week {
            formatter.dateFormat = "EEE"
        } else {
            formatter.dateFormat = "d MMM"
        }
        return formatter.string(from: note.lastModified)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? "New Note" : note.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(note.isDeleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)

            Text("\(timestamp)   \(note.contentPreview)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, EditorTheme.Sidebar.rowPaddingH)
        .padding(.vertical, EditorTheme.Sidebar.rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: EditorTheme.Sidebar.rowCornerRadius)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .contextMenu {
            if note.isDeleted {
                Button("Put Back", action: onRestore)
                Divider()
                Button("Delete Permanently", role: .destructive, action: onPurge)
            } else {
                if !courses.isEmpty {
                    Menu("Move to") {
                        ForEach(courses, id: \.self) { course in
                            Button(course) { onMove(course) }
                        }
                    }
                }
                if note.course != nil {
                    Button("Remove from Course") { onMove(nil) }
                }
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            }
        }
    }

    /// Selection is a quiet fill rather than a card: no border, no shadow, no material.
    private var background: Color {
        if isSelected { return Color.primary.opacity(0.09) }
        if isHovered { return Color.primary.opacity(0.04) }
        return .clear
    }
}

// MARK: - Status

/// The only transient message the editor shows, and only when something is wrong.
private struct StatusPill: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}
