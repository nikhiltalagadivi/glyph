// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

final class GlassStatusLabel: NSTextField {
    nonisolated(unsafe) private var animationTimer: Timer?
    
    var isThinking = false {
        didSet {
            if isThinking {
                startAnimation()
            } else {
                stopAnimation()
            }
            needsDisplay = true
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.needsDisplay = true
            }
        }
        // Ensure it runs during scrolling / tracking
        RunLoop.current.add(animationTimer!, forMode: .common)
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    deinit {
        animationTimer?.invalidate()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isThinking {
            NSGraphicsContext.saveGraphicsState()
            
            let time = CACurrentMediaTime()
            let midX = bounds.width / 2
            let midY = bounds.height / 2
            let radius: CGFloat = 7.0
            
            // Draw track
            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: NSPoint(x: midX, y: midY), radius: radius, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            trackPath.lineWidth = 2.5
            trackPath.stroke()
            
            // Draw spinning arc
            let speed: Double = 1.2
            let startAngle = CGFloat(time * speed * 360).truncatingRemainder(dividingBy: 360)
            let endAngle = startAngle + 100.0 // 100 degree arc
            
            let spinPath = NSBezierPath()
            spinPath.appendArc(withCenter: NSPoint(x: midX, y: midY), radius: radius, startAngle: startAngle, endAngle: endAngle)
            NSColor.labelColor.withAlphaComponent(0.6).setStroke()
            spinPath.lineWidth = 2.5
            spinPath.lineCapStyle = .round
            spinPath.stroke()
            
            NSGraphicsContext.restoreGraphicsState()
        } else {
            super.draw(dirtyRect)
        }
    }
}

// MARK: - TabNote Text View (NSTextView subclass)

class TabNoteTextView: NSTextView {
    weak var editorViewModel: EditorViewModel?

    // Ghost text state
    private var activeSuggestion: SuggestionResult?
    var isInsertingSuggestion = false

    private lazy var ghostLabel: GlassStatusLabel = {
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        cell.isScrollable = false
        cell.alignment = .left
        
        let field = GlassStatusLabel()
        field.cell = cell
        field.textColor = NSColor.placeholderTextColor.withAlphaComponent(0.45)
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.alphaValue = 0
        return field
    }()

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if ghostLabel.superview == nil {
            addSubview(ghostLabel)
        }
    }

    // MARK: Key Handling

    override func keyDown(with event: NSEvent) {
        // ⌘B / ⌘I / ⌘U / ⌘E keyboard shortcuts
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

        // Tab → accept ghost suggestion
        if event.keyCode == 48, activeSuggestion != nil {
            acceptCurrentSuggestion()
            return
        }

        // Escape → dismiss ghost suggestion
        if event.keyCode == 53, activeSuggestion != nil {
            clearSuggestion()
            return
        }

        // Any other key → clear ghost text before processing
        if activeSuggestion != nil {
            clearSuggestion()
        }

        super.keyDown(with: event)
    }

    // Prevent textDidChange from triggering new suggestions while inserting
    override func didChangeText() {
        super.didChangeText()
        if isInsertingSuggestion { return }
        self.needsDisplay = true
    }

    override func layout() {
        super.layout()
        if activeSuggestion != nil {
            positionGhostLabel()
        }
    }

    // MARK: Ghost Text
    
    private var temporaryHighlightRange: NSRange?

    func showSuggestion(_ suggestion: SuggestionResult) {
        guard window?.firstResponder === self,
              !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSuggestion()
            return
        }

        activeSuggestion = suggestion
        ghostLabel.isThinking = false
        ghostLabel.alignment = .left
        
        let firstLine = suggestion.text.components(separatedBy: .newlines).first ?? suggestion.text
        let editorFont = self.font ?? .systemFont(ofSize: 18)

        let styled = NSMutableAttributedString()
        if let hlRange = suggestion.replaceRange {
            styled.append(NSAttributedString(
                string: " ⟲ \(firstLine)",
                attributes: [
                    .font: editorFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ))
            
            // Highlight the text that will be replaced via custom drawing
            if hlRange.length > 0 && NSMaxRange(hlRange) <= (textStorage?.length ?? 0) {
                self.temporaryHighlightRange = hlRange
                self.needsDisplay = true
            }
        } else {
            styled.append(NSAttributedString(
                string: firstLine,
                attributes: [
                    .font: editorFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            ))
        }
        
        let tabImage = createTabKeyImage(font: editorFont)
        let tabAttachment = NSTextAttachment()
        tabAttachment.image = tabImage
        let descent = editorFont.descender
        let yOffset = descent + (editorFont.ascender - descent - tabImage.size.height) / 2
        tabAttachment.bounds = CGRect(x: 0, y: yOffset, width: tabImage.size.width, height: tabImage.size.height)
        
        styled.append(NSAttributedString(string: "  "))
        styled.append(NSAttributedString(attachment: tabAttachment))
        
        ghostLabel.attributedStringValue = styled
        positionGhostLabel()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.ghostLabel.animator().alphaValue = 1
        }
    }

    func clearSuggestion() {
        if temporaryHighlightRange != nil {
            self.temporaryHighlightRange = nil
            self.needsDisplay = true
        }
        
        ghostLabel.isThinking = false
        ghostLabel.alignment = .left
        
        let hadSuggestion = activeSuggestion != nil
        activeSuggestion = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.ghostLabel.animator().alphaValue = 0
        }
        ghostLabel.attributedStringValue = NSAttributedString(string: "")
        if hadSuggestion {
            editorViewModel?.didDismissSuggestion()
        }
    }

    private func acceptCurrentSuggestion() {
        guard let suggestion = activeSuggestion else { return }
        let text = suggestion.text
        let range = selectedRange()

        isInsertingSuggestion = true
        
        self.temporaryHighlightRange = nil
        self.needsDisplay = true

        if let deleteRange = suggestion.replaceRange {
            // Safety: validate deleteRange is within textStorage bounds
            let tsLength = textStorage?.length ?? 0
            guard deleteRange.location >= 0,
                  deleteRange.length >= 0,
                  NSMaxRange(deleteRange) <= tsLength else {
                // Range is invalid — fall through to plain insertion
                isInsertingSuggestion = false
                activeSuggestion = nil
                ghostLabel.alphaValue = 0
                ghostLabel.stringValue = ""
                return
            }

            if let image = createMathImage(for: text) {
                let attachment = NSTextAttachment()
                attachment.image = image
                // Compute baseline offset: align bottom of image with font descender
                let editorFont = self.font ?? NSFont.systemFont(ofSize: 18)
                let descent = editorFont.descender // negative, e.g. -4.2
                let imgHeight = image.size.height
                let lineHeight = editorFont.ascender - editorFont.descender
                let yOffset = descent - (imgHeight - lineHeight) / 2
                attachment.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: image.size)
                
                let attrStr = NSMutableAttributedString(attachment: attachment)
                attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 18), range: NSRange(location: 0, length: 1))
                // Store original LaTeX source so we can recover it for Markdown export
                attrStr.addAttribute(.latexSource, value: text, range: NSRange(location: 0, length: attrStr.length))
                let normalAttrs = [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.labelColor
                ] as [NSAttributedString.Key : Any]
                attrStr.append(NSAttributedString(string: " ", attributes: normalAttrs))
                
                textStorage?.replaceCharacters(in: deleteRange, with: attrStr)
                
                // Keep cursor where it was, or move it if it was inside/after the replaced text
                let newCursorLoc: Int
                if range.location > NSMaxRange(deleteRange) {
                    newCursorLoc = range.location - deleteRange.length + 2
                } else if range.location >= deleteRange.location {
                    newCursorLoc = deleteRange.location + 2
                } else {
                    newCursorLoc = range.location
                }
                setSelectedRange(NSRange(location: newCursorLoc, length: 0))
                
                self.typingAttributes = normalAttrs
                editorViewModel?.updateFormattingState()
            } else {
                let attrText = NSAttributedString(string: text, attributes: typingAttributes)
                textStorage?.replaceCharacters(in: deleteRange, with: attrText)
                
                let newCursorLoc: Int
                if range.location > NSMaxRange(deleteRange) {
                    newCursorLoc = range.location - deleteRange.length + (text as NSString).length
                } else if range.location >= deleteRange.location {
                    newCursorLoc = deleteRange.location + (text as NSString).length
                } else {
                    newCursorLoc = range.location
                }
                setSelectedRange(NSRange(location: newCursorLoc, length: 0))
            }
            
            didChangeText()

        } else {
            if shouldChangeText(in: range, replacementString: text) {
                let attrText = NSAttributedString(string: text, attributes: typingAttributes)
                textStorage?.replaceCharacters(in: range, with: attrText)
                didChangeText()

                let newLoc = range.location + (text as NSString).length
                setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }

        isInsertingSuggestion = false
        activeSuggestion = nil
        ghostLabel.alphaValue = 0
        ghostLabel.stringValue = ""
        
        // Always ensure typing attributes are reset to normal size
        // This prevents the "small text" bug after accepting a math equation
        let normalFont = NSFont.systemFont(ofSize: 18)
        self.typingAttributes[.font] = normalFont
        self.typingAttributes[.foregroundColor] = NSColor.labelColor
        
        editorViewModel?.didAcceptSuggestion()
    }

    private func positionGhostLabel() {
        guard ghostLabel.attributedStringValue.length > 0,
              let lm = layoutManager,
              let tc = textContainer else { return }

        let cursor = selectedRange().location
        let textLen = textStorage?.length ?? 0

        var cursorX: CGFloat = textContainerInset.width
        var cursorY: CGFloat = textContainerInset.height
        var lineHeight: CGFloat = (font?.pointSize ?? 18) * 1.4

        if textLen == 0 {
            cursorX = textContainerInset.width
            cursorY = textContainerInset.height
        } else {
            let charIndex = min(max(0, cursor), textLen)
            if charIndex == textLen, textStorage?.string.hasSuffix("\n") == true {
                let rect = lm.extraLineFragmentRect
                cursorX = rect.minX + textContainerInset.width
                cursorY = rect.minY + textContainerInset.height
                lineHeight = rect.height
            } else {
                let indexForRect = (charIndex == textLen) ? (textLen - 1) : charIndex
                let glyphIdx = lm.glyphIndexForCharacter(at: indexForRect)
                let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 1), in: tc)
                
                cursorY = lineRect.minY + textContainerInset.height
                lineHeight = lineRect.height
                
                if charIndex == textLen {
                    cursorX = rect.maxX + textContainerInset.width
                } else {
                    cursorX = rect.minX + textContainerInset.width
                }
            }
        }

        let maxWidth = max(0, bounds.width - cursorX - textContainerInset.width - 8)
        
        var labelHeight = lineHeight
        var labelY = cursorY
        var labelX = cursorX + 1
        var labelWidth = maxWidth
        
        if ghostLabel.isThinking {
            labelHeight = 22
            labelY = cursorY + (lineHeight - labelHeight) / 2
            labelX = cursorX + 4
            labelWidth = min(36, maxWidth)
        }
        
        ghostLabel.frame = NSRect(
            x: labelX,
            y: labelY,
            width: labelWidth,
            height: labelHeight
        )
    }

    func updateStatusMessage(_ message: String) {
        if activeSuggestion == nil {
            ghostLabel.isThinking = false
            ghostLabel.alignment = .left
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                self.ghostLabel.animator().alphaValue = 0
            }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        
        guard let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        
        if let hlRange = temporaryHighlightRange, hlRange.length > 0 {
            let glyphRange = lm.glyphRange(forCharacterRange: hlRange, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, tc, glyphRangeInLine, _ in
                let intersection = NSIntersectionRange(glyphRange, glyphRangeInLine)
                if intersection.length > 0 {
                    let rect = lm.boundingRect(forGlyphRange: intersection, in: tc)
                    let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                    
                    NSGraphicsContext.saveGraphicsState()
                    
                    let paddedRect = drawRect.insetBy(dx: -4, dy: -2)
                    let path = NSBezierPath(roundedRect: paddedRect, xRadius: 6, yRadius: 6)
                    
                    let isDark = self.effectiveAppearance.name == .darkAqua || self.effectiveAppearance.name == .vibrantDark
                    
                    NSColor.labelColor.withAlphaComponent(isDark ? 0.2 : 0.08).setFill()
                    path.fill()
                    
                    NSColor.labelColor.withAlphaComponent(isDark ? 0.3 : 0.15).setStroke()
                    path.lineWidth = 1.0
                    path.stroke()
                    
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
    }

    // MARK: Formatting

    func toggleBold() {
        let range = selectedRange()
        if range.length > 0 {
            applyFontTrait(.bold, range: range)
        } else {
            toggleTypingFontTrait(.bold)
        }
    }

    func toggleItalic() {
        let range = selectedRange()
        if range.length > 0 {
            applyFontTrait(.italic, range: range)
        } else {
            toggleTypingFontTrait(.italic)
        }
    }

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

    // MARK: Private Formatting Helpers

    private func applyFontTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        range: NSRange
    ) {
        guard let ts = textStorage else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        ts.beginEditing()
        ts.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let newFont: NSFont
            if font.fontDescriptor.symbolicTraits.contains(trait) {
                newFont = fm.convert(font, toNotHaveTrait: mask)
            } else {
                newFont = fm.convert(font, toHaveTrait: mask)
            }
            ts.addAttribute(.font, value: newFont, range: attrRange)
        }
        ts.endEditing()
    }

    private func toggleTypingFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        var attrs = typingAttributes
        guard let font = attrs[.font] as? NSFont else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        if font.fontDescriptor.symbolicTraits.contains(trait) {
            attrs[.font] = fm.convert(font, toNotHaveTrait: mask)
        } else {
            attrs[.font] = fm.convert(font, toHaveTrait: mask)
        }
        typingAttributes = attrs
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        range: NSRange
    ) {
        guard let ts = textStorage else { return }
        ts.beginEditing()

        var hasAttr = false
        ts.enumerateAttribute(key, in: range, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 { hasAttr = true }
        }

        if hasAttr {
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
