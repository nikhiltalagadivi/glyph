// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

@Observable
@MainActor
final class EditorViewModel {
    // Text view reference (set by NSViewRepresentable)
    weak var textView: TabNoteTextView?

    // Current suggestion state
    var currentSuggestion: SuggestionResult?
    var lastAcceptedSuggestionText: String?
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

    func requestSuggestion() {
        suggestionTask?.cancel()
        requestID &+= 1
        let currentID = requestID

        guard let tv = textView else { return }
        let text = tv.string
        let cursor = tv.selectedRange().location
        let selLen = tv.selectedRange().length

        // Need at least 3 chars and no selection
        guard selLen == 0, text.count >= 3 else {
            currentSuggestion = nil
            if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                self.statusMessage = ""
            }
            tv.clearSuggestion()
            return
        }

        // Prevent immediate re-triggering during suggestion insertion
        if tv.isInsertingSuggestion {
            return
        }

        // Check if cursor is immediately preceded by the text attachment character 0xFFFC
        if cursor > 0 {
            let nsText = text as NSString
            for offset in 1...min(2, cursor) {
                if nsText.character(at: cursor - offset) == 0xFFFC {
                    currentSuggestion = nil
                    if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                        self.statusMessage = ""
                    }
                    tv.clearSuggestion()
                    return
                }
            }
        }

        // Don't show "thinking..." immediately to avoid flicker while typing
        if self.statusMessage == "⇥ Tab" {
            self.statusMessage = ""
        }

        let prefix = (text as NSString).substring(to: cursor)
        let isSlashCommand = prefix.range(of: "(?:\\s|^)/[^\\n]*$", options: .regularExpression) != nil
        let isLocalMath = !isSlashCommand && LocalMathTranslator.translate(text: prefix) != nil
        
        let isInstant = isSlashCommand || isLocalMath
        let debounceMs = isInstant ? 100 : 400

        let snapshot = EditorSnapshot(text: text, cursorOffset: cursor)

        suggestionTask = Task { 
            try? await Task.sleep(for: .milliseconds(debounceMs))
            guard !Task.isCancelled else { return }
            
            // 1. If it's a slash command, we query Ollama using the ultra-fast slash AI!
            if isSlashCommand {
                self.statusMessage = "thinking…"
                let result = await self.engine.suggestSlashAI(for: snapshot)
                let msg = await self.engine.statusMessage()

                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }

                if let suggestion = result,
                   suggestion.text != self.lastAcceptedSuggestionText,
                   !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.currentSuggestion = suggestion
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(suggestion)
                } else {
                    self.currentSuggestion = nil
                    self.statusMessage = msg
                    tv.clearSuggestion()
                }
                return
            }
            
            // 2. Otherwise (normal typing), try local translation only
            if let result = await self.engine.suggestLocal(for: snapshot) {
                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }
                
                if result.text != self.lastAcceptedSuggestionText {
                    self.currentSuggestion = result
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(result)
                    return
                }
            }

            // 3. Fallback to Ollama if it might contain math
            if await self.engine.mightContainMath(prefix) {
                self.statusMessage = "thinking…"
                let result = await self.engine.suggestOllama(for: snapshot)
                let msg = await self.engine.statusMessage()

                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }

                if let suggestion = result,
                   suggestion.text != self.lastAcceptedSuggestionText,
                   !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.currentSuggestion = suggestion
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(suggestion)
                    return
                } else {
                    if self.statusMessage == "thinking…" {
                        self.statusMessage = msg
                    }
                }
            }
            
            // 4. Normal typing doesn't match local translation or Ollama -> clear suggestion
            guard !Task.isCancelled, currentID == self.requestID else { return }
            if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                self.statusMessage = ""
            }
            self.textView?.clearSuggestion()
        }
    }

    func didAcceptSuggestion() {
        lastAcceptedSuggestionText = currentSuggestion?.text
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
}

// MARK: - Rich Text Editor (NSViewRepresentable)

