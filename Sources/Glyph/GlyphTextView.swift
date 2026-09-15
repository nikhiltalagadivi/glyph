// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// MARK: - Design Constants

private enum DesignConstants {
    static let ghostFadeInDuration: TimeInterval = 0.2
    static let ghostFadeOutDuration: TimeInterval = 0.1
    static let highlightCornerRadius: CGFloat = 6
    static let highlightPaddingH: CGFloat = 4
    static let highlightPaddingV: CGFloat = 2
    static let highlightBorderWidth: CGFloat = 1.0
}

// MARK: - Glyph Text View

final class GlyphTextView: NSTextView {

    weak var editorViewModel: EditorViewModel?

    // Ghost text state
    private var activeSuggestion: SuggestionResult?

    /// True while we are programmatically inserting text; suppresses re-entrant suggestion triggers.
    private(set) var isInsertingSuggestion = false

    /// Monotonic edit counter. Comparing this is O(1); comparing document strings to
    /// detect staleness was O(document) on every model response.
    private(set) var changeCount: Int = 0

    // MARK: Ghost label

    private let ghostState = GhostPillState()
    private lazy var ghostHostingView: NSHostingView<GhostPillView> = {
        let view = NSHostingView(rootView: GhostPillView(state: ghostState))
        view.alphaValue = 0
        return view
    }()

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if ghostHostingView.superview == nil { addSubview(ghostHostingView) }
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "b":
                toggleBold()
                editorViewModel?.updateFormattingState()
                return
            case "i":
                toggleItalic()
                editorViewModel?.updateFormattingState()
                return
            case "u":
                toggleUnderline()
                editorViewModel?.updateFormattingState()
                return
            case "e":
                editorViewModel?.exportAsMarkdown()
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 48 where activeSuggestion != nil: // Tab
            acceptCurrentSuggestion()
            return
        case 53 where activeSuggestion != nil: // Escape
            clearSuggestion()
            return
        default:
            if activeSuggestion != nil { clearSuggestion() }
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if event.charactersIgnoringModifiers == "z" {
                if let undoManager = self.undoManager, undoManager.canUndo {
                    undoManager.undo()
                    return true
                }
            }
        } else if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers == "z" {
                if let undoManager = self.undoManager, undoManager.canRedo {
                    undoManager.redo()
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func didChangeText() {
        changeCount &+= 1
        super.didChangeText()
        guard !isInsertingSuggestion else { return }
        needsDisplay = true
    }

    override func layout() {
        applyReadableMeasure()
        super.layout()
        if activeSuggestion != nil { positionGhostLabel() }
    }

    /// Keeps the text column at a comfortable width and centres it, rather than letting
    /// lines run the full width of a wide window where the eye loses the return sweep.
    private func applyReadableMeasure() {
        let available = max(0, bounds.width)
        let column = min(EditorTheme.maximumMeasure, available - EditorTheme.minimumSideInset * 2)
        let side = max(EditorTheme.minimumSideInset, (available - column) / 2)
        if abs(textContainerInset.width - side) > 0.5 {
            textContainerInset = NSSize(width: side, height: EditorTheme.topInset)
        }
    }

    // MARK: - Ghost Text Public API

    private var temporaryHighlightRange: NSRange?
    private var slashCommandHighlightRange: NSRange?

    func setSlashCommandHighlight(_ range: NSRange?) {
        if slashCommandHighlightRange != range {
            slashCommandHighlightRange = range
            needsDisplay = true
        }
    }

    func showSuggestion(_ suggestion: SuggestionResult) {
        guard window?.firstResponder === self,
              !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSuggestion()
            return
        }

        activeSuggestion = suggestion
        ghostState.isThinking = false

        let firstLine = suggestion.text.components(separatedBy: .newlines).first ?? suggestion.text
        ghostState.suggestionText = firstLine

        if let hlRange = suggestion.replaceRange {
            if hlRange.length > 0, NSMaxRange(hlRange) <= (textStorage?.length ?? 0) {
                temporaryHighlightRange = hlRange
                needsDisplay = true
            }
        }
        
        // Wait for next run loop to allow SwiftUI view to size itself
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.activeSuggestion != nil else { return }
            self.positionGhostLabel()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = DesignConstants.ghostFadeInDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.ghostHostingView.animator().alphaValue = 1
            }
        }
    }

    func clearSuggestion() {
        if temporaryHighlightRange != nil {
            temporaryHighlightRange = nil
            needsDisplay = true
        }

        ghostState.isThinking = false

        let hadSuggestion = activeSuggestion != nil
        activeSuggestion = nil

        // Clear content immediately so it doesn't flash during fade-out
        ghostState.suggestionText = ""

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DesignConstants.ghostFadeOutDuration
            ghostHostingView.animator().alphaValue = 0
        }

        if hadSuggestion { editorViewModel?.didDismissSuggestion() }
    }

    func showThinkingIndicator() {
        guard activeSuggestion == nil else { return }
        ghostState.isThinking = true
        ghostState.suggestionText = ""
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.ghostState.isThinking else { return }
            self.positionGhostLabel()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = DesignConstants.ghostFadeInDuration
                self.ghostHostingView.animator().alphaValue = 1
            }
        }
    }

    func hideThinkingIndicator() {
        guard activeSuggestion == nil else { return }
        ghostState.isThinking = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = DesignConstants.ghostFadeOutDuration
            ghostHostingView.animator().alphaValue = 0
        }
    }

    /// Previously unused `message` parameter is now wired to the thinking indicator.
    func updateStatusMessage(_ message: String) {
        guard activeSuggestion == nil else { return }
        if message.isEmpty {
            hideThinkingIndicator()
        } else {
            showThinkingIndicator()
        }
    }

    /// Rebuilds every equation attachment from its stored LaTeX, picking up the
    /// current text colour. Does not mark the document dirty: nothing textual changed.
    func refreshEquationImages() {
        guard let ts = textStorage, ts.length > 0 else { return }
        restyleEquations(in: NSRange(location: 0, length: ts.length))
    }

    /// Re-renders the equations overlapping `range` in whichever style now suits them.
    ///
    /// Typing next to a standalone equation turns it from display into inline style, so
    /// this runs after edits. It only ever changes attributes, never the string, so it
    /// cannot re-enter the change notification that triggered it.
    func restyleEquations(in range: NSRange) {
        guard let ts = textStorage, ts.length > 0 else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ts.length))
        guard clamped.length > 0 else { return }

        let editorFont = font ?? EditorTheme.body
        var updates: [(NSRange, NSTextAttachment)] = []

        ts.enumerateAttribute(.latexSource, in: clamped, options: []) { value, subrange, _ in
            guard let source = value as? String else { return }
            let style = mathStyle(for: subrange, in: ts)
            guard let image = createMathImage(for: source, style: style) else { return }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = mathAttachmentBounds(imageSize: image.size, font: editorFont)
            updates.append((subrange, attachment))
        }
        guard !updates.isEmpty else { return }

        ts.beginEditing()
        for (subrange, attachment) in updates {
            ts.addAttribute(.attachment, value: attachment, range: subrange)
        }
        ts.endEditing()
        needsDisplay = true
    }

    /// Restyles just the paragraph the caret sits in — cheap enough to run on every edit.
    func restyleEquationsAroundCaret() {
        guard let ts = textStorage, ts.length > 0 else { return }
        let text = ts.string as NSString
        let caret = min(selectedRange().location, text.length)
        let paragraph = text.paragraphRange(for: NSRange(location: max(0, caret - 1), length: 0))
        restyleEquations(in: paragraph)
    }

    /// Brings a document onto the current type scale.
    ///
    /// Notes written before the redesign carry the old system sans; this converts them
    /// to the editor face while keeping any bold or italic the writer applied.
    func normalizeTypography() {
        guard let ts = textStorage, ts.length > 0 else { return }
        let full = NSRange(location: 0, length: ts.length)
        let targetFamily = EditorTheme.body.familyName

        ts.beginEditing()
        ts.addAttribute(.paragraphStyle, value: EditorTheme.bodyParagraphStyle, range: full)
        ts.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            guard attrs[.attachment] == nil else { return }
            guard let existing = attrs[.font] as? NSFont else {
                ts.addAttribute(.font, value: EditorTheme.body, range: range)
                return
            }
            guard existing.familyName != targetFamily else { return }
            let descriptor = EditorTheme.body.fontDescriptor
                .withSymbolicTraits(existing.fontDescriptor.symbolicTraits)
            let converted = NSFont(descriptor: descriptor, size: existing.pointSize) ?? EditorTheme.body
            ts.addAttribute(.font, value: converted, range: range)
        }
        ts.endEditing()
    }

    // MARK: - Title styling

    /// The first line of a note is its title, so it is set as one.
    ///
    /// Only the size changes: bold or italic the writer applied is carried across, and
    /// a line that stops being the first line is demoted back to body size.
    func enforceTitleStyle() {
        guard let ts = textStorage, ts.length > 0 else { return }
        let text = ts.string as NSString
        let first = text.paragraphRange(for: NSRange(location: 0, length: 0))

        ts.beginEditing()
        resize(ts, in: first, to: EditorTheme.titleSize, paragraphStyle: EditorTheme.titleParagraphStyle)

        // A newline typed at the end of the title carries the title font forward.
        if NSMaxRange(first) < text.length {
            let second = text.paragraphRange(for: NSRange(location: NSMaxRange(first), length: 0))
            resize(ts, in: second, to: EditorTheme.bodySize, paragraphStyle: EditorTheme.bodyParagraphStyle)
        }
        ts.endEditing()
    }

    private func resize(
        _ ts: NSTextStorage,
        in range: NSRange,
        to size: CGFloat,
        paragraphStyle: NSParagraphStyle
    ) {
        guard range.length > 0 else { return }
        // Skip the write when nothing would change: this runs on every keystroke and
        // each attribute change invalidates layout for the paragraph.
        let existingStyle = ts.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
        if (existingStyle as? NSParagraphStyle) != paragraphStyle {
            ts.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        ts.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            // Equation attachments are positioned against their own font; leave them be.
            guard attrs[.attachment] == nil else { return }
            guard let font = attrs[.font] as? NSFont, font.pointSize != size else { return }
            let resized = NSFontManager.shared.convert(font, toSize: size)
            ts.addAttribute(.font, value: resized, range: subrange)
        }
    }

    // MARK: - Copying

    /// Copying anything that contains an equation puts real LaTeX on the pasteboard.
    ///
    /// This is the bridge out of the app: notes go into a problem set, an Overleaf
    /// document or a message to a TA without anyone retyping the maths. Every other
    /// editor hands over an image or an object-replacement character here.
    override func copy(_ sender: Any?) {
        guard writeLatexSelectionToPasteboard() else {
            super.copy(sender)
            return
        }
    }

    override func cut(_ sender: Any?) {
        if writeLatexSelectionToPasteboard() {
            insertText("", replacementRange: selectedRange())
        } else {
            super.cut(sender)
        }
    }

    /// Writes the selection to the general pasteboard, with equations as LaTeX in the
    /// plain-text flavour and as their rendered image in the rich flavour.
    ///
    /// NSTextView normally fills the pasteboard lazily, which would overwrite anything
    /// written alongside it, so the whole pasteboard is declared here with no owner.
    private func writeLatexSelectionToPasteboard() -> Bool {
        guard let ts = textStorage else { return false }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }

        let plain = ranges
            .map { latexPlainText(in: $0, storage: ts) }
            .joined(separator: "\n")
        guard !plain.isEmpty else { return false }

        let rich = NSMutableAttributedString()
        for range in ranges {
            if rich.length > 0 { rich.append(NSAttributedString(string: "\n")) }
            rich.append(ts.attributedSubstring(from: range))
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.rtfd, .rtf, .string], owner: nil)

        let full = NSRange(location: 0, length: rich.length)
        if let rtfd = rich.rtfd(from: full, documentAttributes: [:]) {
            pasteboard.setData(rtfd, forType: .rtfd)
        }
        if let rtf = rich.rtf(from: full, documentAttributes: [:]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(plain, forType: .string)
        return true
    }

    private func latexPlainText(in range: NSRange, storage ts: NSTextStorage) -> String {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: ts.length))
        guard clamped.length > 0 else { return "" }

        let text = ts.string as NSString
        var result = ""
        result.reserveCapacity(clamped.length)
        ts.enumerateAttributes(in: clamped, options: []) { attrs, subrange, _ in
            if attrs[.attachment] != nil, let latex = attrs[.latexSource] as? String {
                result += latex
            } else {
                result += text.substring(with: subrange)
            }
        }
        return result
    }

    /// The whole document as plain text with equations expanded — used for export and
    /// for building the search index.
    func latexPlainText() -> String {
        guard let ts = textStorage else { return "" }
        return latexPlainText(in: NSRange(location: 0, length: ts.length), storage: ts)
    }

    // MARK: - Scanning windows

    /// The slice of text the scanner should look at, and where it starts.
    struct ScanWindow {
        let text: String
        /// UTF-16 offset of `text` within the document.
        let offset: Int
        /// Whether `text` starts at a real line boundary. False when a very long line
        /// was clipped, in which case position-in-line cannot be trusted.
        let startsLine: Bool
    }

    /// The tail of the document before the caret, bounded so per-keystroke scanning
    /// costs the same in a 200-word note and a 200-page one.
    ///
    /// The window always begins on a line or word boundary, so a clipped fragment can
    /// never be mistaken for a token.
    func scanWindow(upTo cursor: Int) -> ScanWindow {
        guard let ts = textStorage else { return ScanWindow(text: "", offset: 0, startsLine: true) }
        let text = ts.string as NSString
        let end = min(max(0, cursor), text.length)
        guard end > 0 else { return ScanWindow(text: "", offset: 0, startsLine: true) }

        let windowStart = max(0, end - Self.scanWindowLength)
        var offset = windowStart
        var startsLine = windowStart == 0

        if windowStart > 0 {
            let searchRange = NSRange(location: windowStart, length: end - windowStart)
            let newline = text.rangeOfCharacter(from: .newlines, options: [], range: searchRange)
            if newline.location != NSNotFound {
                offset = NSMaxRange(newline)
                startsLine = true
            } else {
                let space = text.rangeOfCharacter(from: .whitespaces, options: [], range: searchRange)
                if space.location != NSNotFound { offset = NSMaxRange(space) }
            }
        }

        guard offset < end else { return ScanWindow(text: "", offset: offset, startsLine: startsLine) }
        return ScanWindow(
            text: text.substring(with: NSRange(location: offset, length: end - offset)),
            offset: offset,
            startsLine: startsLine
        )
    }

    /// A `/command` running from a slash at the start of a line (or after whitespace)
    /// up to the caret.
    struct SlashCommand {
        /// Document range covering the slash and everything after it.
        let range: NSRange
        /// The command text, without the slash.
        let instruction: String
    }

    func slashCommand(in window: ScanWindow) -> SlashCommand? {
        let text = window.text as NSString
        // Only the last line can hold the active command.
        let newline = text.rangeOfCharacter(from: .newlines, options: .backwards)
        let lineStart = newline.location == NSNotFound ? 0 : NSMaxRange(newline)

        // If the window itself was clipped mid-line we cannot tell where the line began.
        guard newline.location != NSNotFound || window.startsLine else { return nil }

        // Only a slash that opens the line is a command: "x = 1 / 2" is division.
        var slashIndex = lineStart
        while slashIndex < text.length,
              let scalar = Unicode.Scalar(text.character(at: slashIndex)),
              CharacterSet.whitespaces.contains(scalar) {
            slashIndex += 1
        }
        guard slashIndex < text.length, text.character(at: slashIndex) == 47 else { return nil } // "/"

        let length = text.length - slashIndex
        let instruction = text
            .substring(with: NSRange(location: slashIndex + 1, length: length - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SlashCommand(
            range: NSRange(location: window.offset + slashIndex, length: length),
            instruction: instruction
        )
    }

    /// Plain-text context for the model, with rendered equations expanded back to
    /// their LaTeX source. Bounded for the same reason as `scanWindow`.
    func contextText(upTo cursor: Int) -> String {
        guard let ts = textStorage else { return "" }
        let end = min(max(0, cursor), ts.length)
        let start = max(0, end - Self.contextWindowLength)
        guard start < end else { return "" }

        let text = ts.string as NSString
        var result = ""
        result.reserveCapacity(end - start)
        ts.enumerateAttributes(in: NSRange(location: start, length: end - start), options: []) { attrs, subrange, _ in
            if attrs[.attachment] != nil, let latex = attrs[.latexSource] as? String {
                result += latex
            } else {
                result += text.substring(with: subrange)
            }
        }
        return result
    }

    private static let scanWindowLength = 1_000
    private static let contextWindowLength = 1_200

    // MARK: - Private: Accept Suggestion

    private func acceptCurrentSuggestion() {
        guard let suggestion = activeSuggestion else { return }

        isInsertingSuggestion = true
        temporaryHighlightRange = nil
        needsDisplay = true

        defer {
            isInsertingSuggestion = false
            activeSuggestion = nil
            ghostHostingView.alphaValue = 0
            ghostState.suggestionText = ""
            // Reset typing attributes to prevent "small text" bug after math insertion
            resetTypingAttributes()
            editorViewModel?.didAcceptSuggestion()
        }

        if let deleteRange = suggestion.replaceRange {
            guard isValidRange(deleteRange) else { return }
            insertSuggestionWithReplacement(text: suggestion.text, replaceRange: deleteRange)
        } else {
            insertSuggestionAtCursor(text: suggestion.text)
        }
    }

    private func insertSuggestionWithReplacement(text: String, replaceRange: NSRange) {
        let priorCursor = selectedRange().location

        // Build the replacement first. `shouldChangeText` records the undo snapshot
        // using the length of the string it is handed, so handing it the LaTeX source
        // while inserting a two-character attachment run left undo unable to restore
        // the original phrase.
        let replacement: NSAttributedString
        if let image = createMathImage(for: text) {
            replacement = mathAttachmentString(
                image: image,
                source: text,
                font: font ?? EditorTheme.body
            )
        } else {
            replacement = NSAttributedString(string: text, attributes: typingAttributes)
        }

        guard shouldChangeText(in: replaceRange, replacementString: replacement.string) else { return }

        textStorage?.replaceCharacters(in: replaceRange, with: replacement)
        setSelectedRange(NSRange(
            location: updatedCursorPosition(
                prior: priorCursor,
                replaceRange: replaceRange,
                insertedLength: replacement.length
            ),
            length: 0
        ))

        didChangeText()
    }

    private func insertSuggestionAtCursor(text: String) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: text) else { return }
        let attrStr = NSAttributedString(string: text, attributes: typingAttributes)
        textStorage?.replaceCharacters(in: range, with: attrStr)
        didChangeText()
        let newLoc = range.location + (text as NSString).length
        setSelectedRange(NSRange(location: newLoc, length: 0))
    }

    // MARK: - Private: Ghost Label Helpers

    private func positionGhostLabel() {
        guard !ghostState.suggestionText.isEmpty || ghostState.isThinking,
              let lm = layoutManager,
              let tc = textContainer else { return }

        let cursor = selectedRange().location
        let textLen = textStorage?.length ?? 0
        let editorFont = font ?? .systemFont(ofSize: EditorTheme.bodySize)
        
        // Ensure layout is complete before querying metrics
        lm.ensureLayout(for: tc)

        let (cursorX, cursorY, lineHeight) = cursorMetrics(
            cursor: cursor,
            textLen: textLen,
            layoutManager: lm,
            textContainer: tc,
            fallbackFont: editorFont
        )

        let pillSize = ghostHostingView.fittingSize
        let labelWidth = min(pillSize.width, max(0, bounds.width - cursorX - textContainerInset.width - 8))
        let labelHeight = pillSize.height
        let labelX = cursorX + 6
        let labelY = cursorY + (lineHeight - labelHeight) / 2

        ghostHostingView.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
    }

    /// Returns (cursorX, cursorY, lineHeight) for the current insertion point.
    private func cursorMetrics(
        cursor: Int,
        textLen: Int,
        layoutManager lm: NSLayoutManager,
        textContainer tc: NSTextContainer,
        fallbackFont: NSFont
    ) -> (x: CGFloat, y: CGFloat, lineHeight: CGFloat) {
        let insetX = textContainerInset.width
        let insetY = textContainerInset.height
        let defaultLineHeight = fallbackFont.pointSize * 1.4

        guard textLen > 0 else {
            return (insetX, insetY, defaultLineHeight)
        }

        // Cursor is past the last character and that last char is a newline
        if cursor == textLen, textStorage?.string.hasSuffix("\n") == true {
            let rect = lm.extraLineFragmentRect
            return (rect.minX + insetX, rect.minY + insetY, rect.height)
        }

        let clampedIndex = min(max(0, cursor), textLen)
        let rectIndex = clampedIndex == textLen ? textLen - 1 : clampedIndex
        let glyphIdx = lm.glyphIndexForCharacter(at: rectIndex)
        let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
        let glyphLocation = lm.location(forGlyphAt: glyphIdx)
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 1), in: tc)

        let x = clampedIndex == textLen
            ? lineRect.minX + glyphLocation.x + glyphRect.width + insetX
            : lineRect.minX + glyphLocation.x + insetX
        return (x, lineRect.minY + insetY, lineRect.height)
    }

    // MARK: - Private: Cursor Utilities

    /// Computes where the cursor should land after replacing `replaceRange` with `insertedLength` chars.
    private func updatedCursorPosition(prior: Int, replaceRange: NSRange, insertedLength: Int) -> Int {
        if prior > NSMaxRange(replaceRange) {
            return prior - replaceRange.length + insertedLength
        } else if prior >= replaceRange.location {
            return replaceRange.location + insertedLength
        }
        return prior
    }

    private func isValidRange(_ range: NSRange) -> Bool {
        let tsLength = textStorage?.length ?? 0
        return range.location >= 0
            && range.length >= 0
            && NSMaxRange(range) <= tsLength
    }

    private func resetTypingAttributes() {
        typingAttributes = EditorTheme.bodyAttributes
        editorViewModel?.updateFormattingState()
    }

    // MARK: - Custom Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let lm = layoutManager, textContainer != nil else { return }
        let origin = textContainerOrigin
        let isDark = effectiveAppearance.name == .darkAqua || effectiveAppearance.name == .vibrantDark

        // The span a slash command will replace, tinted with the system accent.
        if let scRange = slashCommandHighlightRange, scRange.length > 0 {
            fill(
                range: scRange,
                layoutManager: lm,
                origin: origin,
                color: EditorTheme.accent.withAlphaComponent(isDark ? 0.22 : 0.14),
                inset: 3
            )
        }

        // The span a suggestion will replace, in plain monochrome.
        if let hlRange = temporaryHighlightRange, hlRange.length > 0 {
            fill(
                range: hlRange,
                layoutManager: lm,
                origin: origin,
                color: NSColor.labelColor.withAlphaComponent(isDark ? 0.14 : 0.07),
                inset: 3
            )
        }
    }

    /// Paints a rounded fill behind every line fragment a character range covers.
    private func fill(
        range: NSRange,
        layoutManager lm: NSLayoutManager,
        origin: NSPoint,
        color: NSColor,
        inset: CGFloat
    ) {
        let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, container, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersection.length > 0 else { return }

            let rect = lm.boundingRect(forGlyphRange: intersection, in: container)
                .offsetBy(dx: origin.x, dy: origin.y)
                .insetBy(dx: -inset, dy: -1)
            let path = NSBezierPath(
                roundedRect: rect,
                xRadius: DesignConstants.highlightCornerRadius,
                yRadius: DesignConstants.highlightCornerRadius
            )
            color.setFill()
            path.fill()
        }
    }

    // MARK: - Formatting

    func toggleBold() { toggleFontTrait(.bold) }
    func toggleItalic() { toggleFontTrait(.italic) }

    func toggleUnderline() {
        let range = selectedRange()
        if range.length > 0 {
            toggleAttribute(.underlineStyle, range: range)
        } else {
            toggleTypingAttribute(.underlineStyle)
        }
    }

    func toggleStrikethrough() {
        let range = selectedRange()
        if range.length > 0 {
            toggleAttribute(.strikethroughStyle, range: range)
        } else {
            toggleTypingAttribute(.strikethroughStyle)
        }
    }

    // MARK: - Private Formatting Helpers

    private func toggleFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        let range = selectedRange()
        if range.length > 0 {
            applyFontTrait(trait, range: range)
        } else {
            toggleTypingFontTrait(trait)
        }
    }

    private func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, range: NSRange) {
        guard let ts = textStorage else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        ts.beginEditing()
        ts.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let newFont = font.fontDescriptor.symbolicTraits.contains(trait)
                ? fm.convert(font, toNotHaveTrait: mask)
                : fm.convert(font, toHaveTrait: mask)
            ts.addAttribute(.font, value: newFont, range: attrRange)
        }
        ts.endEditing()
    }

    private func toggleTypingFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        var attrs = typingAttributes
        guard let font = attrs[.font] as? NSFont else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        attrs[.font] = font.fontDescriptor.symbolicTraits.contains(trait)
            ? fm.convert(font, toNotHaveTrait: mask)
            : fm.convert(font, toHaveTrait: mask)
        typingAttributes = attrs
    }

    /// Toggles a style attribute (underline or strikethrough) over a range.
    private func toggleAttribute(_ key: NSAttributedString.Key, range: NSRange) {
        guard let ts = textStorage else { return }
        ts.beginEditing()

        var isActive = false
        ts.enumerateAttribute(key, in: range, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 { isActive = true }
        }

        if isActive {
            ts.removeAttribute(key, range: range)
        } else {
            ts.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        ts.endEditing()
    }

    private func toggleTypingAttribute(_ key: NSAttributedString.Key) {
        var attrs = typingAttributes
        let current = (attrs[key] as? Int) ?? 0
        if current != 0 {
            attrs.removeValue(forKey: key)
        } else {
            attrs[key] = NSUnderlineStyle.single.rawValue
        }
        typingAttributes = attrs
    }
}
