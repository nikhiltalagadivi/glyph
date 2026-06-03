// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// MARK: - Design Constants

private enum DesignConstants {
    static let editorFontSize: CGFloat = 18
    static let spinnerRadius: CGFloat = 7.0
    static let spinnerLineWidth: CGFloat = 2.5
    static let spinnerArcDegrees: CGFloat = 100
    static let spinnerSpeed: Double = 1.2
    static let ghostFadeInDuration: TimeInterval = 0.2
    static let ghostFadeOutDuration: TimeInterval = 0.1
    static let highlightCornerRadius: CGFloat = 6
    static let highlightPaddingH: CGFloat = 4
    static let highlightPaddingV: CGFloat = 2
    static let highlightBorderWidth: CGFloat = 1.0
    static let ghostThinkingWidth: CGFloat = 36
    static let ghostThinkingHeight: CGFloat = 22
}

// MARK: - Spinner View (CADisplayLink-driven, zero-overhead when idle)

final class GlassStatusLabel: NSTextField {

    var isThinking = false
}

// MARK: - TabNote Text View

final class TabNoteTextView: NSTextView {

    weak var editorViewModel: EditorViewModel?

    // Ghost text state
    private var activeSuggestion: SuggestionResult?

    /// True while we are programmatically inserting text; suppresses re-entrant suggestion triggers.
    private(set) var isInsertingSuggestion = false

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

    override func didChangeText() {
        super.didChangeText()
        guard !isInsertingSuggestion else { return }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        if activeSuggestion != nil { positionGhostLabel() }
    }

    // MARK: - Ghost Text Public API

    private var temporaryHighlightRange: NSRange?

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

        if let image = createMathImage(for: text) {
            let attrStr = mathAttachmentString(image: image, source: text)
            textStorage?.replaceCharacters(in: replaceRange, with: attrStr)
            let insertedLength = attrStr.length
            setSelectedRange(NSRange(
                location: updatedCursorPosition(
                    prior: priorCursor,
                    replaceRange: replaceRange,
                    insertedLength: insertedLength
                ),
                length: 0
            ))
        } else {
            let attrStr = NSAttributedString(string: text, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: replaceRange, with: attrStr)
            setSelectedRange(NSRange(
                location: updatedCursorPosition(
                    prior: priorCursor,
                    replaceRange: replaceRange,
                    insertedLength: (text as NSString).length
                ),
                length: 0
            ))
        }

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

    private func appendTabKeyBadge(to string: NSMutableAttributedString, font: NSFont) {
        let tabImage = createTabKeyImage(font: font)
        let attachment = NSTextAttachment()
        attachment.image = tabImage
        let descent = font.descender
        let yOffset = descent + (font.ascender - descent - tabImage.size.height) / 2
        attachment.bounds = CGRect(x: 0, y: yOffset, width: tabImage.size.width, height: tabImage.size.height)
        string.append(NSAttributedString(string: "  "))
        string.append(NSAttributedString(attachment: attachment))
    }

    private func positionGhostLabel() {
        guard !ghostState.suggestionText.isEmpty || ghostState.isThinking,
              let lm = layoutManager,
              let tc = textContainer else { return }

        let cursor = selectedRange().location
        let textLen = textStorage?.length ?? 0
        let editorFont = font ?? .systemFont(ofSize: DesignConstants.editorFontSize)
        
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

    // MARK: - Private: Math Attachment Builder

    private func mathAttachmentString(image: NSImage, source: String) -> NSMutableAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        let editorFont = font ?? NSFont.systemFont(ofSize: DesignConstants.editorFontSize)
        let descent = editorFont.descender
        let lineHeight = editorFont.ascender - editorFont.descender
        let yOffset = descent - (image.size.height - lineHeight) / 2
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: image.size)

        let attrStr = NSMutableAttributedString(attachment: attachment)
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: DesignConstants.editorFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        attrStr.addAttributes(normalAttrs, range: NSRange(location: 0, length: 1))
        attrStr.addAttribute(.latexSource, value: source, range: NSRange(location: 0, length: attrStr.length))
        attrStr.append(NSAttributedString(string: " ", attributes: normalAttrs))
        return attrStr
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
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: DesignConstants.editorFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        editorViewModel?.updateFormattingState()
    }

    // MARK: - Custom Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let hlRange = temporaryHighlightRange, hlRange.length > 0,
              let lm = layoutManager, let tc = textContainer else { return }

        let origin = textContainerOrigin
        let glyphRange = lm.glyphRange(forCharacterRange: hlRange, actualCharacterRange: nil)
        let isDark = effectiveAppearance.name == .darkAqua || effectiveAppearance.name == .vibrantDark

        lm.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] _, _, lineTC, lineGlyphRange, _ in
            guard self != nil else { return }
            let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard intersection.length > 0 else { return }

            let rect = lm.boundingRect(forGlyphRange: intersection, in: lineTC)
            let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)
            let paddedRect = drawRect.insetBy(
                dx: -DesignConstants.highlightPaddingH,
                dy: -DesignConstants.highlightPaddingV
            )
            let path = NSBezierPath(roundedRect: paddedRect,
                                    xRadius: DesignConstants.highlightCornerRadius,
                                    yRadius: DesignConstants.highlightCornerRadius)

            NSGraphicsContext.saveGraphicsState()
            NSColor.labelColor.withAlphaComponent(isDark ? 0.2 : 0.08).setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(isDark ? 0.3 : 0.15).setStroke()
            path.lineWidth = DesignConstants.highlightBorderWidth
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
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
