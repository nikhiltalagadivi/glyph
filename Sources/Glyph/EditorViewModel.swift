// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers
import GlyphMath

// Custom key to store LaTeX source on text attachments for Markdown export

@Observable
@MainActor
final class EditorViewModel {
    // Text view reference (set by NSViewRepresentable)
    weak var textView: GlyphTextView? {
        didSet {
            if textView != nil {
                loadSelectedNoteIntoTextView()
            }
        }
    }

    // Notes list state
    var notes: [GlyphNote] = []
    var searchQuery = ""
    var selectedNote: GlyphNote? {
        didSet {
            if !isTextLoading {
                loadSelectedNoteIntoTextView()
            }
        }
    }
    
    /// Notes matching the current search.
    ///
    /// Equations are part of the index: because every attachment keeps its LaTeX
    /// source, searching "sqrt" or "infty" finds the formula, not just the prose
    /// around it. In every other editor a rendered equation is opaque to search.
    var filteredNotes: [GlyphNote] {
        let live = notes.filter { !$0.isDeleted }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return live }
        return live.filter { $0.matches(query) }
    }

    /// Notes waiting in Recently Deleted, newest first.
    var deletedNotes: [GlyphNote] {
        notes.filter(\.isDeleted).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    static let recentlyDeletedName = "Recently Deleted"

    /// Course names, most recently worked on first.
    var courses: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for note in notes where !note.isDeleted {
            guard let course = note.course, !course.isEmpty else { continue }
            if seen.insert(course).inserted { ordered.append(course) }
        }
        return ordered
    }

    static let unfiledCourseName = "Unfiled"

    /// Notes grouped under their course heading.
    var groupedNotes: [NoteSection] {
        var order: [String] = []
        var buckets: [String: [GlyphNote]] = [:]

        for note in filteredNotes {
            let key = note.course?.isEmpty == false ? note.course! : Self.unfiledCourseName
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(note)
        }

        // Unfiled always sits at the bottom, however recently it was touched.
        if let index = order.firstIndex(of: Self.unfiledCourseName) {
            order.remove(at: index)
            order.append(Self.unfiledCourseName)
        }

        var sections = order.compactMap { key -> NoteSection? in
            guard let notes = buckets[key] else { return nil }
            return NoteSection(id: key, notes: notes)
        }

        let deleted = deletedNotes
        if !deleted.isEmpty, searchQuery.isEmpty {
            sections.append(NoteSection(id: Self.recentlyDeletedName, notes: deleted))
        }
        return sections
    }

    /// Whether the floating status message should be shown.
    ///
    /// "thinking…" is deliberately excluded: the caret already shows animated dots
    /// while the model works, and a second indicator for the same thing is noise.
    var showsStatus: Bool {
        !statusMessage.isEmpty && statusMessage != "thinking…"
    }

    func assignSelectedNote(to course: String?) {
        guard let note = selectedNote else { return }
        setCourse(course, for: note)
    }

    /// Files a note under a course, or unfiles it when `course` is nil.
    func setCourse(_ course: String?, for note: GlyphNote) {
        let cleaned = course?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (cleaned?.isEmpty == false) ? cleaned : nil

        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].course = value
        notes[index].lastModified = Date()
        let updated = notes[index]

        if selectedNote?.id == note.id {
            isTextLoading = true
            selectedNote = updated
            isTextLoading = false
        }
        writeNoteToDisk(updated)
    }

    private var isTextLoading = false
    private var saveTask: Task<Void, Never>?
    /// Set when the document differs from what is on disk.
    private var isDirty = false
    /// Guards against `scanAndRenderRawLatex` re-entering itself via `didChangeText`.
    private var isRenderingLatex = false

    /// The view model lives for the whole app session, so the observer is never
    /// removed explicitly — it is torn down with the process.
    private nonisolated(unsafe) static var terminationObserver: (any NSObjectProtocol)?

    init() {
        loadAllNotes()
        // A note edited within the last debounce window must still reach disk on quit.
        Self.terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        }
    }



    // Current suggestion state
    var currentSuggestion: SuggestionResult?
    var statusMessage = "" {
        didSet {
            textView?.updateStatusMessage(statusMessage)
        }
    }

    // Formatting state (reflects selection / typing attributes)
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStrikethrough = false

    // Engine
    private let engine = OllamaSuggestionEngine(runtime: BundledOllamaRuntime())
    private var suggestionTask: Task<Void, Never>?
    private var requestID: UInt64 = 0

    // MARK: Formatting

    func toggleBold() {
        textView?.toggleBold()
        updateFormattingState()
        refocusTextView()
    }

    func toggleItalic() {
        textView?.toggleItalic()
        updateFormattingState()
        refocusTextView()
    }

    func toggleUnderline() {
        textView?.toggleUnderline()
        updateFormattingState()
        refocusTextView()
    }

    func toggleStrikethrough() {
        textView?.toggleStrikethrough()
        updateFormattingState()
        refocusTextView()
    }

    func updateFormattingState() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let attrs: [NSAttributedString.Key: Any]

        if range.length > 0, let ts = tv.textStorage, range.location < ts.length {
            attrs = ts.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
        } else {
            isBold = false
            isItalic = false
        }
        isUnderlined = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
    }

    private func refocusTextView() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: Suggestions

    func startupAI() async {
        let pollTask = Task {
            while !Task.isCancelled {
                let msg = await engine.statusMessage()
                if self.statusMessage != msg && self.currentSuggestion == nil {
                    self.statusMessage = msg
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        await engine.warmup()
        pollTask.cancel()
        if self.currentSuggestion == nil {
            self.statusMessage = ""
        }
    }

    /// Called on every keystroke.
    ///
    /// Three tiers, cheapest first:
    ///   1. `/command` — an explicit request for the model, but still translated
    ///      locally first when the command is plain transcription.
    ///   2. The deterministic parser, which answers in microseconds with no network.
    ///   3. The local model, debounced, only for phrases the parser declined.
    func requestSuggestion() {
        suggestionTask?.cancel()
        requestID &+= 1
        let currentID = requestID

        guard let tv = textView, let ts = tv.textStorage else { return }

        // Suppress the re-entrant trigger caused by inserting a suggestion.
        guard !tv.isInsertingSuggestion else { return }

        let selection = tv.selectedRange()
        guard selection.length == 0, ts.length >= 3 else {
            dismissSuggestion(on: tv)
            return
        }

        let cursor = selection.location
        let window = tv.scanWindow(upTo: cursor)
        guard !window.text.isEmpty else {
            dismissSuggestion(on: tv)
            return
        }

        // ---- Tier 1: slash command -------------------------------------------------
        if let slash = tv.slashCommand(in: window) {
            tv.setSlashCommandHighlight(slash.range)

            // A bare "/" is not yet a command; highlight it and wait for the rest.
            guard !slash.instruction.isEmpty else {
                currentSuggestion = nil
                tv.clearSuggestion()
                return
            }

            // Even a slash command gets the instant path when it is pure transcription.
            if let local = MathTranslator.translate(slash.instruction) {
                present(SuggestionResult(text: local.inlineDelimited, replaceRange: slash.range), on: tv)
                return
            }

            let context = tv.contextText(upTo: slash.range.location)
            suggestionTask = makeModelTask(
                id: currentID,
                kind: .command,
                phrase: slash.instruction,
                context: context,
                replaceRange: slash.range,
                debounce: .milliseconds(120),
                documentVersion: tv.changeCount,
                cursor: cursor
            )
            return
        }
        tv.setSlashCommandHighlight(nil)

        // ---- Tier 2: deterministic translation -------------------------------------
        if let scan = MathScopeScanner.scan(prefix: window.text) {
            let range = NSRange(location: window.offset + scan.range.location, length: scan.range.length)
            guard NSMaxRange(range) <= ts.length else {
                dismissSuggestion(on: tv)
                return
            }
            present(SuggestionResult(text: scan.inlineDelimited, replaceRange: range), on: tv)
            return
        }

        // ---- Tier 3: model fallback ------------------------------------------------
        guard let llmRange = MathScopeScanner.llmRange(prefix: window.text) else {
            dismissSuggestion(on: tv)
            return
        }
        let range = NSRange(location: window.offset + llmRange.location, length: llmRange.length)
        guard NSMaxRange(range) <= ts.length else {
            dismissSuggestion(on: tv)
            return
        }

        let phrase = (ts.string as NSString).substring(with: range)
        let context = tv.contextText(upTo: range.location)
        suggestionTask = makeModelTask(
            id: currentID,
            kind: .translation,
            phrase: phrase,
            context: context,
            replaceRange: range,
            debounce: .milliseconds(280),
            documentVersion: tv.changeCount,
            cursor: cursor
        )
    }

    /// Shows a suggestion that was produced synchronously — no spinner, no flicker.
    private func present(_ suggestion: SuggestionResult, on tv: GlyphTextView) {
        currentSuggestion = suggestion
        // Order matters: showing the pill first makes `updateStatusMessage` a no-op,
        // so the thinking dots are replaced rather than faded out and back in.
        tv.showSuggestion(suggestion)
        statusMessage = ""
    }

    private func dismissSuggestion(on tv: GlyphTextView) {
        currentSuggestion = nil
        if statusMessage == "thinking…" { statusMessage = "" }
        tv.setSlashCommandHighlight(nil)
        tv.clearSuggestion()
    }

    private func makeModelTask(
        id: UInt64,
        kind: SuggestionKind,
        phrase: String,
        context: String,
        replaceRange: NSRange,
        debounce: Duration,
        documentVersion: Int,
        cursor: Int
    ) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }

            self.statusMessage = "thinking…"
            let result = await self.engine.suggest(
                kind: kind,
                phrase: phrase,
                context: context,
                replaceRange: replaceRange
            )
            let engineMessage = await self.engine.statusMessage()

            guard !Task.isCancelled, id == self.requestID, let tv = self.textView else { return }
            // Cheap staleness check: comparing whole document strings was O(document).
            guard tv.changeCount == documentVersion,
                  tv.selectedRange() == NSRange(location: cursor, length: 0) else { return }

            if let result, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.present(result, on: tv)
            } else {
                self.currentSuggestion = nil
                self.statusMessage = engineMessage
                tv.clearSuggestion()
            }
        }
    }

    func didAcceptSuggestion() {
        currentSuggestion = nil
        statusMessage = ""
    }

    func didDismissSuggestion() {
        currentSuggestion = nil
        statusMessage = ""
    }

    // MARK: Export

    func exportAsMarkdown() {
        guard let tv = textView, let ts = tv.textStorage else { return }

        var markdown = ""
        let fullRange = NSRange(location: 0, length: ts.length)

        ts.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            // Check for text attachment (rendered LaTeX)
            if attrs[.attachment] is NSTextAttachment {
                // Try to recover stored LaTeX source
                if let latex = attrs[.latexSource] as? String {
                    markdown += latex
                } else {
                    markdown += "[equation]"
                }
                return
            }

            let substring = ts.attributedSubstring(from: range).string

            // Determine formatting
            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isUnderline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let isStrike = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0

            var text = substring
            // Apply Markdown formatting (innermost first)
            if isStrike { text = "~~\(text)~~" }
            if isUnderline { text = "<u>\(text)</u>" }
            if isBold && isItalic { text = "***\(text)***" }
            else if isBold { text = "**\(text)**" }
            else if isItalic { text = "_\(text)_" }

            markdown += text
        }

        // Show save panel
        let panel = NSSavePanel()
        panel.title = "Export as Markdown"
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }

    func exportAsLaTeX() {
        guard let tv = textView, let ts = tv.textStorage else { return }

        var bodyContent = ""
        let fullRange = NSRange(location: 0, length: ts.length)

        ts.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            if attrs[.attachment] is NSTextAttachment {
                if let latex = attrs[.latexSource] as? String {
                    let cleanLatex = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanLatex.hasPrefix("\\[") && cleanLatex.hasSuffix("\\]") {
                        bodyContent += "\n" + cleanLatex + "\n"
                    } else {
                        bodyContent += " " + cleanLatex + " "
                    }
                } else {
                    bodyContent += "[attachment]"
                }
                return
            }

            let substring = ts.attributedSubstring(from: range).string

            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isUnderline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let isStrike = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0

            var text = substring
            text = text.replacingOccurrences(of: "\\", with: "\\textbackslash{}")
                       .replacingOccurrences(of: "{", with: "\\{")
                       .replacingOccurrences(of: "}", with: "\\}")
                       .replacingOccurrences(of: "$", with: "\\$")
                       .replacingOccurrences(of: "%", with: "\\%")
                       .replacingOccurrences(of: "&", with: "\\&")
                       .replacingOccurrences(of: "_", with: "\\_")
                       .replacingOccurrences(of: "#", with: "\\#")
                       .replacingOccurrences(of: "~", with: "\\textasciitilde{}")
                       .replacingOccurrences(of: "^", with: "\\textasciicircum{}")
            
            if isStrike { text = "\\sout{\(text)}" }
            if isUnderline { text = "\\underline{\(text)}" }
            if isBold && isItalic { text = "\\textbf{\\textit{\(text)}}" }
            else if isBold { text = "\\textbf{\(text)}" }
            else if isItalic { text = "\\textit{\(text)}" }

            bodyContent += text
        }

        let title = selectedNote?.title ?? "Untitled"
        let latexDocument = """
\\documentclass{article}
\\usepackage{amsmath}
\\usepackage{amssymb}
\\usepackage{ulem}
\\usepackage[utf8]{inputenc}

\\title{\(title)}
\\date{\\today}

\\begin{document}
\\maketitle

\(bodyContent)

\\end{document}
"""

        let panel = NSSavePanel()
        panel.title = "Export as LaTeX"
        panel.nameFieldStringValue = "\(title.replacingOccurrences(of: " ", with: "_")).tex"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        panel.canCreateDirectories = true

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try latexDocument.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("LaTeX export failed: \(error)")
            }
        }
    }

    func exportAsPDF() {
        guard let tv = textView, let ts = tv.textStorage else { return }
        
        let panel = NSSavePanel()
        panel.title = "Export as PDF"
        let title = selectedNote?.title ?? "Untitled"
        panel.nameFieldStringValue = "\(title.replacingOccurrences(of: " ", with: "_")).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            
            // Create a temporary layout system for printing
            let printInfo = NSPrintInfo.shared
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            
            // Calculate paper size & margins
            let paperSize = printInfo.paperSize
            let leftMargin = printInfo.leftMargin
            let rightMargin = printInfo.rightMargin
            let topMargin = printInfo.topMargin
            let bottomMargin = printInfo.bottomMargin
            let printWidth = paperSize.width - leftMargin - rightMargin
            let printHeight = paperSize.height - topMargin - bottomMargin
            
            // 1. Create a copy of the text storage
            let printAttributedString = NSMutableAttributedString(attributedString: ts)
            let fullRange = NSRange(location: 0, length: printAttributedString.length)
            
            // 2. Clear background color and force text/foreground color to black
            printAttributedString.addAttribute(.foregroundColor, value: NSColor.black, range: fullRange)
            if printAttributedString.length > 0 {
                printAttributedString.removeAttribute(.backgroundColor, range: fullRange)
            }
            
            // 3. Re-render every equation in black, for white paper.
            let editorFont = tv.font ?? NSFont.systemFont(ofSize: 18)
            printAttributedString.enumerateAttribute(.latexSource, in: fullRange, options: []) { value, range, _ in
                guard let latexSource = value as? String,
                      let image = createMathImage(for: latexSource, color: .black) else { return }
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = mathAttachmentBounds(imageSize: image.size, font: editorFont)
                printAttributedString.addAttribute(.attachment, value: attachment, range: range)
            }
            
            // 4. Set up temporary printing NSTextView
            let printStorage = NSTextStorage(attributedString: printAttributedString)
            let layoutManager = NSLayoutManager()
            printStorage.addLayoutManager(layoutManager)
            
            let textContainer = NSTextContainer(containerSize: NSSize(width: printWidth, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = true
            layoutManager.addTextContainer(textContainer)
            
            let printTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: printWidth, height: printHeight), textContainer: textContainer)
            printTextView.backgroundColor = .white
            
            // Trigger layout calculation
            layoutManager.ensureLayout(for: textContainer)
            
            // Adjust frame height to accommodate all content
            let usedRect = layoutManager.usedRect(for: textContainer)
            printTextView.frame = NSRect(x: 0, y: 0, width: printWidth, height: max(usedRect.height, printHeight))
            
            // 5. Run the print operation on the printTextView
            let printOp = NSPrintOperation(view: printTextView, printInfo: printInfo)
            printOp.showsPrintPanel = false
            printOp.showsProgressPanel = false
            
            let success = printOp.run()
            if !success {
                print("PDF Export failed")
            }
        }
    }

    /// One alternation covering every delimiter style, compiled once.
    ///
    /// `$$…$$` precedes `$…$` so the display form wins at the same position, and no
    /// inner group matches a newline, so a stray `$` cannot swallow a paragraph.
    ///
    /// The single-dollar form follows the usual convention: its content may not begin
    /// or end with a space and the closing `$` may not be followed by a digit. That is
    /// what keeps "it cost $5 and $6" from being rendered as an equation.
    private static let rawLatexRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\$\$([^$\n]+)\$\$|\\\[([^\n]+?)\\\]|\\\(([^\n]+?)\\\)|\$([^\s$][^$\n]*?[^\s$]|[^\s$])\$(?!\d)"#
    )

    /// Turns literal LaTeX the user typed (`$x^2$`, `\( … \)`) into a rendered equation.
    ///
    /// Matches are applied right to left in a single pass: replacing a match shifts
    /// every range after it, so processing forwards — or once per delimiter style, as
    /// this used to — corrupts the later ranges.
    func scanAndRenderRawLatex() {
        guard !isRenderingLatex, let tv = textView, let ts = tv.textStorage else { return }
        guard let regex = Self.rawLatexRegex else { return }

        let text = ts.string as NSString
        let cursor = min(tv.selectedRange().location, text.length)
        let paragraphRange = text.paragraphRange(for: NSRange(location: max(0, cursor - 1), length: 0))
        guard paragraphRange.length > 0 else { return }

        let paragraph = text.substring(with: paragraphRange)
        let matches = regex.matches(
            in: paragraph,
            range: NSRange(location: 0, length: (paragraph as NSString).length)
        )
        guard !matches.isEmpty else { return }

        isRenderingLatex = true
        defer { isRenderingLatex = false }

        let editorFont = tv.font ?? .systemFont(ofSize: 18)
        var didReplace = false

        for match in matches.reversed() {
            let absolute = NSRange(
                location: paragraphRange.location + match.range.location,
                length: match.range.length
            )
            guard NSMaxRange(absolute) <= ts.length else { continue }
            guard !containsRenderedEquation(ts, in: absolute) else { continue }

            let source = text.substring(with: absolute)
            guard let image = createMathImage(for: source) else { continue }

            let replacement = mathAttachmentString(
                image: image,
                source: source,
                font: editorFont,
                includeTrailingSpace: false
            )
            guard tv.shouldChangeText(in: absolute, replacementString: replacement.string) else { continue }

            let caret = tv.selectedRange().location
            ts.beginEditing()
            ts.replaceCharacters(in: absolute, with: replacement)
            ts.endEditing()

            if caret >= NSMaxRange(absolute) {
                let delta = replacement.length - absolute.length
                tv.setSelectedRange(NSRange(location: max(0, caret + delta), length: 0))
            }
            didReplace = true
        }

        if didReplace { tv.didChangeText() }
    }

    private func containsRenderedEquation(_ storage: NSTextStorage, in range: NSRange) -> Bool {
        var found = false
        storage.enumerateAttributes(in: range, options: []) { attrs, _, stop in
            if attrs[.attachment] != nil || attrs[.latexSource] != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: Notes Management

    var notesDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("com.tabnote.app", isDirectory: true)
        let notes = appSupport.appendingPathComponent("Notes", isDirectory: true)
        return notes
    }

    func ensureNotesDirectoryExists() {
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    func loadAllNotes() {
        ensureNotesDirectoryExists()
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: notesDirectory, includingPropertiesForKeys: nil) else { return }
        
        var loadedNotes: [GlyphNote] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let note = try? JSONDecoder().decode(GlyphNote.self, from: data) {
                loadedNotes.append(note)
            }
        }
        
        notes = loadedNotes.sorted { $0.lastModified > $1.lastModified }
        
        if notes.allSatisfy(\.isDeleted) {
            createDefaultNote()
        } else {
            selectedNote = notes.first { !$0.isDeleted }
        }
    }

    func createDefaultNote() {
        let welcomeText = """
Welcome to Glyph
Write maths at the speed you write words.
Type it in plain English and press Tab when the suggestion appears:
• the area is pi r squared
• x squared plus y squared equals z squared
• the integral from 0 to 1 of x squared dx
• the limit as x approaches 0 of sin x over x
• the derivative of y with respect to x
Shorthand works too — E = mc^2, dy/dx, sqrt(x^2 + y^2), 1/2 m v squared.
Find it again. Search covers your equations, not just your prose: looking for "sqrt" or "integral" finds the formula itself. Press Command F.
Take it with you. Select anything and copy — equations arrive as real LaTeX, ready to paste into Overleaf, a problem set, or an email to your TA. Export the whole note as Markdown, LaTeX or PDF from the ••• menu.
Keep it organised. File each note under a course from the ••• menu. Deleted notes wait in Recently Deleted until you say otherwise.
Need something worked out rather than written out? Start a line with a slash:
  /differentiate y with respect to x
  /solve for m
"""
        let welcomeAttr = NSMutableAttributedString(
            string: welcomeText,
            attributes: EditorTheme.bodyAttributes
        )
        
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: welcomeAttr, requiringSecureCoding: false) else { return }
        
        let newNote = GlyphNote(
            id: UUID(),
            title: "Welcome to Glyph",
            contentPreview: "A minimalist writing environment powered by local intelligence.",
            lastModified: Date(),
            richTextData: data
        )
        
        notes = [newNote]
        selectedNote = newNote
        writeNoteToDisk(newNote)
    }

    func createNewNote() {
        flushPendingSave()
        let emptyStr = NSAttributedString(string: "", attributes: EditorTheme.titleAttributes)
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: emptyStr, requiringSecureCoding: false) else { return }
        
        let newNote = GlyphNote(
            id: UUID(),
            title: "New Note",
            contentPreview: "No additional text",
            lastModified: Date(),
            richTextData: data
        )
        
        notes.insert(newNote, at: 0)
        selectedNote = newNote
        writeNoteToDisk(newNote)
    }

    /// Moves a note to Recently Deleted. Nothing leaves the disk.
    func deleteNote(_ note: GlyphNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }

        if selectedNote?.id == note.id {
            // Drop any queued write, or the debounce would resurrect it as a live note.
            saveTask?.cancel()
            saveTask = nil
            isDirty = false
        }

        notes[index].deletedAt = Date()
        let deleted = notes[index]
        writeNoteToDisk(deleted)

        if selectedNote?.id == note.id {
            selectedNote = notes.first { !$0.isDeleted }
        }
        if notes.allSatisfy(\.isDeleted) { createNewNote() }
    }

    func restoreNote(_ note: GlyphNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].deletedAt = nil
        notes[index].lastModified = Date()
        let restored = notes[index]
        writeNoteToDisk(restored)
        notes.sort { $0.lastModified > $1.lastModified }
        select(restored)
    }

    /// The only path that actually erases a file, and it is never a shortcut.
    func permanentlyDelete(_ note: GlyphNote) {
        notes.removeAll { $0.id == note.id }
        let fileURL = notesDirectory.appendingPathComponent("\(note.id).json")
        try? FileManager.default.removeItem(at: fileURL)

        if selectedNote?.id == note.id {
            selectedNote = notes.first { !$0.isDeleted }
        }
        if notes.allSatisfy(\.isDeleted) { createNewNote() }
    }

    func writeNoteToDisk(_ note: GlyphNote) {
        ensureNotesDirectoryExists()
        let fileURL = notesDirectory.appendingPathComponent("\(note.id).json")
        do {
            let data = try JSONEncoder().encode(note)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save note to disk: \(error)")
        }
    }

    // MARK: Loading

    private func loadSelectedNoteIntoTextView() {
        guard let tv = textView else { return }
        guard let note = selectedNote else {
            tv.textStorage?.setAttributedString(NSAttributedString())
            return
        }

        isTextLoading = true
        defer { isTextLoading = false }

        guard let loaded = Self.unarchive(note.richTextData) else {
            tv.textStorage?.setAttributedString(NSAttributedString(string: "", attributes: Self.defaultAttributes))
            tv.typingAttributes = EditorTheme.titleAttributes
            tv.undoManager?.removeAllActions()
            updateFormattingState()
            return
        }

        tv.textStorage?.setAttributedString(loaded)
        // Equation images are not stored on disk; they are rebuilt from the LaTeX
        // source travelling with each attachment, in whichever style now suits them.
        tv.normalizeTypography()
        tv.enforceTitleStyle()
        tv.refreshEquationImages()
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        // The undo stack belongs to the note that was open; keeping it would let
        // Command-Z splice text from one note into another.
        tv.undoManager?.removeAllActions()
        updateFormattingState()
    }

    private static func unarchive(_ data: Data) -> NSAttributedString? {
        guard !data.isEmpty,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] { EditorTheme.bodyAttributes }

    // MARK: Saving

    /// Selecting a note from the sidebar. Flushes the note being left so nothing
    /// typed in the last debounce window is lost.
    func select(_ note: GlyphNote) {
        guard note.id != selectedNote?.id else { return }
        flushPendingSave()
        selectedNote = note
    }

    /// Runs on every keystroke, so it does only cheap work: the title and preview come
    /// from the plain string, and the attributed text is serialised later.
    func noteContentDidChange() {
        guard !isTextLoading, let tv = textView, let ts = tv.textStorage,
              let note = selectedNote else { return }

        let (title, preview) = Self.summarize(ts)
        var updated = note
        updated.title = title
        updated.contentPreview = preview
        updated.lastModified = Date()

        isTextLoading = true
        selectedNote = updated
        isTextLoading = false

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = updated
            // The edited note is by definition the most recent, so it belongs at the
            // front. Moving one element beats re-sorting the whole list per keystroke.
            if index != 0 {
                notes.remove(at: index)
                notes.insert(updated, at: 0)
            }
        }

        isDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    /// Serialises the document and writes it. Called from the debounce, when switching
    /// notes, and on quit.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty, let ts = textView?.textStorage, var note = selectedNote else { return }
        isDirty = false

        guard let data = Self.archive(ts) else { return }
        note.richTextData = data
        note.searchText = textView?.latexPlainText().lowercased()

        isTextLoading = true
        selectedNote = note
        isTextLoading = false
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note }

        writeNoteToDisk(note)
    }

    /// Archives the document without the rendered equation bitmaps.
    ///
    /// Each equation carries a baked 3× image weighing hundreds of kilobytes. Keeping
    /// them turned every save into megabytes of encoding; the LaTeX source alone is a
    /// few dozen bytes and the images are rebuilt on load.
    private static func archive(_ storage: NSTextStorage) -> Data? {
        let copy = NSMutableAttributedString(attributedString: storage)
        let fullRange = NSRange(location: 0, length: copy.length)
        copy.enumerateAttribute(.latexSource, in: fullRange, options: []) { value, range, _ in
            guard value is String else { return }
            copy.removeAttribute(.attachment, range: range)
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: copy, requiringSecureCoding: false)
    }

    /// Sidebar title and preview, derived from the plain text only.
    private static func summarize(_ storage: NSTextStorage) -> (title: String, preview: String) {
        let lines = storage.string.components(separatedBy: .newlines)

        var title = "New Note"
        if let first = lines.first {
            let cleaned = first
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { title = String(cleaned.prefix(100)) }
        }

        var preview = "No additional text"
        for line in lines.dropFirst() {
            let cleaned = line
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                preview = String(cleaned.prefix(120))
                break
            }
        }

        if preview == "No additional text", storage.string.contains("\u{FFFC}") {
            preview = "Mathematical formula"
        }
        return (title, preview)
    }
}

struct NoteSection: Identifiable {
    let id: String
    let notes: [GlyphNote]
}

// MARK: - Rich Text Editor (NSViewRepresentable)

